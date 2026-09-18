package app.archivewatch.android

import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.archivewatch.android.studio.RtmpPublisher
import app.archivewatch.android.studio.RtmpStreamConfig
import app.archivewatch.android.studio.StudioGl
import app.archivewatch.android.studio.StudioProgramGl
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
 * A REAL FILM through the whole Android chain, on real hardware
 * (docs/WATCH-TOGETHER.md §6.2b): ExoPlayer decodes an archive.org mp4 into a
 * `SurfaceTexture`, GLES samples it as an external OES texture and draws it
 * aspect-fit into MediaCodec's input surface, and our publisher sends the
 * result to a real server.
 *
 * The flat-colour test proved the chain MOVES. This proves it carries the
 * FILM — a different question, and the one where an external texture sampled
 * with the wrong sampler, or a missing transform matrix, shows up.
 */
@RunWith(AndroidJUnit4::class)
class StudioFilmDeviceTest {

    private val args = InstrumentationRegistry.getArguments()
    private val host: String = args.getString("rtmpHost") ?: "10.0.0.90"
    private val port = 19351
    private val filmUrl: String = args.getString("filmUrl")
        // A SMALL film by default. The Wedding March is 1.1 GB and a TV
        // dongle will not have it playing inside a test's patience; what is
        // under test is the texture path, not the CDN.
        ?: "https://dn600307.us.archive.org/0/items/PreviewTheKissOfDeath/preview%20-%20The%20Kiss%20of%20Death.mp4"

    private fun serverIsUp(): Boolean = try {
        Socket().use { it.connect(InetSocketAddress(host, port), 1500); true }
    } catch (_: Exception) { false }

    @Test fun publishesARealFilm() {
        assumeTrue("no RTMP server at $host:$port — skipping", serverIsUp())

        val w = 1280; val h = 720; val fps = 30
        val enc = StudioVideoEncoder(w, h, fps, 4_000_000)
        enc.start()
        val gl = StudioGl(enc.inputSurface)
        gl.setUp()
        val programGl = StudioProgramGl(w, h)
        programGl.setUp()

        // ExoPlayer lives on the main thread; the GL context lives here.
        val instr = InstrumentationRegistry.getInstrumentation()
        var player: ExoPlayer? = null
        instr.runOnMainSync {
            val p = ExoPlayer.Builder(instr.targetContext).build()
            p.setVideoSurface(Surface(programGl.filmSurfaceTexture))
            p.setMediaItem(MediaItem.fromUri(filmUrl))
            p.prepare()
            p.playWhenReady = true
            player = p
        }
        assertNotNull(player)

        // Wait for the film to actually start producing frames before
        // measuring anything — a network film needs a moment.
        var n = 0
        while (n < 600 && programGl.framesAvailable.get() < 5) {
            gl.makeCurrent()
            programGl.updateFilmFrame()
            gl.clear(0f, 0f, 0f)
            programGl.drawFilm(4f / 3f)
            gl.swap(n.toLong() * 1_000_000_000L / fps)
            enc.drain { _, _, _ -> }
            n++
            Thread.sleep(30)
        }
        // The DECODER's own callback, not updateTexImage()'s return. The
        // latter succeeds with nothing new and re-presents the last frame, so
        // it can never tell you a film is playing.
        assertTrue("the film delivered no frames in ~18s (got ${programGl.framesAvailable.get()})",
                   programGl.framesAvailable.get() >= 5)

        val avcC = run {
            var guard = 0
            while (enc.avcC == null && guard < 60) {
                gl.makeCurrent(); programGl.updateFilmFrame()
                gl.clear(0f, 0f, 0f); programGl.drawFilm(4f / 3f)
                gl.swap((n + guard).toLong() * 1_000_000_000L / fps)
                enc.drain { _, _, _ -> }
                guard++
            }
            enc.avcC
        }
        assertNotNull("MediaCodec never produced an avcC record", avcC)

        val p = RtmpPublisher()
        p.publish(
            "rtmp://$host:$port/live", "androidfilm",
            RtmpStreamConfig(
                width = w, height = h, frameRate = fps.toDouble(), videoBitrate = 4_000_000,
                avcC = avcC!!,
                audioSampleRate = 44100, audioChannels = 1, audioBitrate = 128_000,
                audioSpecificConfig = RealAac.asc
            ),
            declareAudio = false
        )

        var frame = n + 60
        val deadline = System.currentTimeMillis() + 25_000
        while (System.currentTimeMillis() < deadline) {
            gl.makeCurrent()
            programGl.updateFilmFrame()
            gl.clear(0f, 0f, 0f)
            programGl.drawFilm(4f / 3f)
            gl.swap(frame.toLong() * 1_000_000_000L / fps)
            enc.drain { a, k, t -> p.sendVideo(a, k, t, t) }
            frame++
            Thread.sleep(25)
        }
        enc.drain { a, k, t -> p.sendVideo(a, k, t, t) }

        // A failure here must SAY what it saw. "almost nothing was encoded"
        // sent me to the logcat for a number the test already had.
        val report = "encoded=${p.health.videoFramesSent} bytes=${p.health.bytesSent} " +
                     "filmFrames=${programGl.framesAvailable.get()} drawn=$frame " +
                     "state=${p.health.state} err=${p.health.lastError}"
        // A MODEST bar, deliberately. This test asks "does the film reach the
        // encoder", not "how fast" — and on a TV dongle pulling an mp4 over
        // the network it is slow: 26 film frames and 39 encoded in 25 s,
        // measured 2026-09-17. Throughput is its own measurement on its own
        // hardware, and asserting a number this test was never shaped to
        // produce is how a green suite starts lying.
        assertTrue("almost nothing was encoded — $report", p.health.videoFramesSent > 20)
        // The film must still be DELIVERING at the end, not merely have
        // started: a decoder that stalls leaves a still picture that every
        // other counter calls healthy (§9).
        assertTrue("the film stopped delivering frames during the broadcast — $report",
                   programGl.framesAvailable.get() > 10)
        assertEquals("the connection did not survive the film — $report", "publishing", p.health.state)
        Thread.sleep(1500)
        p.close()
        instr.runOnMainSync { player?.release() }
        programGl.tearDown(); gl.tearDown(); enc.stop()
    }
}
