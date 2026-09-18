package app.archivewatch.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import app.archivewatch.android.studio.RtmpPublisher
import app.archivewatch.android.studio.RtmpStreamConfig
import app.archivewatch.android.studio.StudioGl
import app.archivewatch.android.studio.StudioVideoEncoder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.InetSocketAddress
import java.net.Socket

/**
 * The real Android encode path on real hardware: GLES draws into MediaCodec's
 * input surface, MediaCodec encodes, and our own publisher sends it to a real
 * server (docs/WATCH-TOGETHER.md §6.2).
 *
 * No film and no camera yet — a flat colour is enough to prove the chain
 * MOVES, and proving the chain before adding sources is what kept the Apple
 * side honest. What this catches is exactly what a synthetic frame catches:
 * a wrong EGL config, a missing presentation time, Annex-B left unconverted.
 */
@RunWith(AndroidJUnit4::class)
class StudioEncoderDeviceTest {

    private val host: String =
        androidx.test.platform.app.InstrumentationRegistry.getArguments()
            .getString("rtmpHost") ?: "10.0.0.90"
    private val port = 19351

    private fun serverIsUp(): Boolean = try {
        Socket().use { it.connect(InetSocketAddress(host, port), 1500); true }
    } catch (_: Exception) { false }

    @Test fun encodesWithMediaCodecAndPublishes() {
        assumeTrue("no RTMP server at $host:$port — skipping", serverIsUp())

        val w = 1280; val h = 720; val fps = 30
        val enc = StudioVideoEncoder(w, h, fps, 4_000_000)
        enc.start()
        val gl = StudioGl(enc.inputSurface)
        gl.setUp()

        // Draw a few frames first so the encoder produces its format (and so
        // avcC exists) before the publisher needs it.
        val frames = ArrayList<Triple<ByteArray, Boolean, Int>>()
        var n = 0
        while (enc.avcC == null && n < 30) {
            drawOne(gl, n, fps); n++
            enc.drain { a, k, t -> frames.add(Triple(a, k, t)) }
        }
        assertNotNull("MediaCodec never produced an avcC record", enc.avcC)
        val avcC = enc.avcC!!
        // configurationVersion is 1 and lengthSizeMinusOne is 3 — the two
        // bytes a malformed record gets wrong.
        assertEquals(1.toByte(), avcC[0])
        assertEquals(0xFF.toByte(), avcC[4])

        val p = RtmpPublisher()
        p.publish(
            "rtmp://$host:$port/live", "androidencode",
            RtmpStreamConfig(
                width = w, height = h, frameRate = fps.toDouble(), videoBitrate = 4_000_000,
                avcC = avcC,
                audioSampleRate = 44100, audioChannels = 1, audioBitrate = 128_000,
                audioSpecificConfig = RealAac.asc
            ),
            declareAudio = false
        )
        enc.requestKeyframe()
        for ((a, k, t) in frames) p.sendVideo(a, k, t, t)

        // Then keep drawing until the server has had plenty — a short burst
        // measures the burst, not the encoder (§6.2a).
        while (n < 400) {
            drawOne(gl, n, fps); n++
            enc.drain { a, k, t -> p.sendVideo(a, k, t, t) }
        }
        Thread.sleep(500)
        enc.drain { a, k, t -> p.sendVideo(a, k, t, t) }

        assertTrue("the encoder produced nothing", p.health.videoFramesSent > 100)
        assertEquals("the connection did not survive the encode", "publishing", p.health.state)
        Thread.sleep(2000)
        p.close(); gl.tearDown(); enc.stop()
    }

    /** A colour that changes every frame, so the encoder has real work. */
    private fun drawOne(gl: StudioGl, n: Int, fps: Int) {
        gl.makeCurrent()
        val t = n / 60f
        gl.clear(0.5f + 0.5f * kotlin.math.sin(t), 0.35f, 0.5f + 0.5f * kotlin.math.cos(t))
        gl.swap(n.toLong() * 1_000_000_000L / fps)
    }
}
