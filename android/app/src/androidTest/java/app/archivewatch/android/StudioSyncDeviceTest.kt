package app.archivewatch.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.archivewatch.android.studio.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.InetSocketAddress
import java.net.Socket
import kotlin.math.sin

/**
 * A/V ALIGNMENT, measured rather than asserted (docs/WATCH-TOGETHER.md §9).
 *
 * The Apple side has 10 ms over 15 s. Android had "the starts agree at
 * 0.000000", which is not the same claim — audio timestamps come from BYTES
 * CONSUMED and video from the frame counter, two clocks that share an origin
 * only by construction, and drift is exactly what construction alone does not
 * rule out.
 *
 * So this publishes a signal it CONTROLS rather than a film's own content
 * (Decision 075, controlled experiments over correlation): once a second, one
 * WHITE frame is drawn at the same instant a full-scale tone burst is fed to
 * the audio encoder. Both are stamped from the SAME nanosecond clock. The
 * offset between flash and burst in the server's recording is the number, and
 * `tools/measure_av_sync.py` reads it off the file.
 *
 * A flat black frame and silence between markers keeps both easy to find and
 * keeps the bitrate low enough that nothing is dropped for bandwidth.
 */
@RunWith(AndroidJUnit4::class)
class StudioSyncDeviceTest {

    private val args = InstrumentationRegistry.getArguments()
    private val host: String = args.getString("rtmpHost") ?: "10.0.0.90"
    private val port = 19351
    private val seconds = (args.getString("syncSeconds") ?: "20").toInt()

    private fun serverIsUp(): Boolean = try {
        Socket().use { it.connect(InetSocketAddress(host, port), 1500); true }
    } catch (_: Exception) { false }

    @Test fun publishesASynchronisedMarkerSignal() {
        assumeTrue("no RTMP server at $host:$port — skipping", serverIsUp())

        val w = 1280; val h = 720; val fps = 30
        val rate = 44100; val channels = 1
        val enc = StudioVideoEncoder(w, h, fps, 2_000_000).also { it.start() }
        val gl = StudioGl(enc.inputSurface).also { it.setUp() }
        val aac = StudioAacEncoder(rate, channels).also { it.start() }

        // Prime both encoders so their configs exist before publishing — a
        // stream's tracks are declared once, at publish (§6.2g).
        var frame = 0L
        while ((enc.avcC == null || aac.asc == null) && frame < 200) {
            drawFlat(gl, frame, fps, white = false)
            aac.encode(silence(rate / fps * 2))
            enc.drain { _, _, _ -> }; aac.drain { _, _ -> }
            frame++
        }
        assertNotNull("no avcC", enc.avcC)
        assertNotNull("no AudioSpecificConfig", aac.asc)

        val p = RtmpPublisher()
        p.publish("rtmp://$host:$port/live", "androidsync",
            RtmpStreamConfig(w, h, fps.toDouble(), 2_000_000, enc.avcC!!,
                             rate, channels, 96_000, aac.asc!!))
        enc.requestKeyframe()

        // One marker a second: a white frame and a tone burst on the SAME
        // frame index, so any offset in the recording is the pipeline's and
        // not the test's.
        val totalFrames = seconds * fps
        var markers = 0
        while (frame < totalFrames) {
            val isMarker = (frame % fps) == 0L && frame > 0
            drawFlat(gl, frame, fps, white = isMarker)
            aac.encode(if (isMarker) tone(rate / fps, rate) else silence(rate / fps * 2))
            if (isMarker) markers++
            enc.drain { a, k, t -> p.sendVideo(a, k, t, t) }
            aac.drain { a, t -> p.sendAudio(a, t) }
            frame++
            Thread.sleep((1000L / fps).coerceAtLeast(1))
        }
        enc.drain { a, k, t -> p.sendVideo(a, k, t, t) }
        aac.drain { a, t -> p.sendAudio(a, t) }

        val report = "markers=$markers frames=$frame video=${p.health.videoFramesSent} " +
                     "state=${p.health.state}"
        assertTrue("too few markers — $report", markers >= seconds - 2)
        assertEquals("the connection did not survive — $report", "publishing", p.health.state)
        Thread.sleep(1500)
        p.close(); gl.tearDown(); enc.stop(); aac.stop()
    }

    private fun drawFlat(gl: StudioGl, frame: Long, fps: Int, white: Boolean) {
        gl.makeCurrent()
        if (white) gl.clear(1f, 1f, 1f) else gl.clear(0f, 0f, 0f)
        gl.swap(frame * 1_000_000_000L / fps)
    }

    /** 16-bit mono silence, `frames` samples. */
    private fun silence(bytes: Int) = ByteArray(bytes)

    /** A full-scale 1 kHz burst — unmistakable against silence. */
    private fun tone(frames: Int, rate: Int): ByteArray {
        val out = ByteArray(frames * 2)
        for (i in 0 until frames) {
            val v = (sin(2.0 * Math.PI * 1000.0 * i / rate) * 32000).toInt().toShort()
            out[i * 2] = (v.toInt() and 0xFF).toByte()
            out[i * 2 + 1] = ((v.toInt() shr 8) and 0xFF).toByte()
        }
        return out
    }
}
