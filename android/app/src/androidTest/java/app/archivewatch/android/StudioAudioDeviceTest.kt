package app.archivewatch.android

import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
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

/**
 * THE FILM'S AUDIO, tapped and broadcast (docs/WATCH-TOGETHER.md §6.2):
 * `TeeAudioProcessor` copies decoded PCM out of ExoPlayer, MediaCodec turns it
 * into AAC, and the publisher sends it as a real second track.
 *
 * The bar is deliberately not "an audio track exists". A correctly plumbed
 * SILENCE would satisfy that, and silence is precisely what a broken tap
 * produces — so the tap reports its PEAK and the test insists the film was
 * actually heard.
 */
@UnstableApi
@RunWith(AndroidJUnit4::class)
class StudioAudioDeviceTest {

    private val args = InstrumentationRegistry.getArguments()
    private val host: String = args.getString("rtmpHost") ?: "10.0.0.90"
    private val port = 19351
    // A film with a real soundtrack. The silents this project mostly carries
    // would make a peak assertion meaningless.
    private val filmUrl = args.getString("filmUrl")
        ?: "https://archive.org/download/Popeye_forPresident/Popeye_forPresident_512kb.mp4"

    private fun serverIsUp(): Boolean = try {
        Socket().use { it.connect(InetSocketAddress(host, port), 1500); true }
    } catch (_: Exception) { false }

    @Test fun tapsAndPublishesTheFilmsAudio() {
        assumeTrue("no RTMP server at $host:$port — skipping", serverIsUp())

        val w = 1280; val h = 720; val fps = 30
        val enc = StudioVideoEncoder(w, h, fps, 4_000_000); enc.start()
        val gl = StudioGl(enc.inputSurface); gl.setUp()
        val pg = StudioProgramGl(w, h); pg.setUp()

        val tap = StudioFilmAudioTap()
        val instr = InstrumentationRegistry.getInstrumentation()
        var player: ExoPlayer? = null
        instr.runOnMainSync {
            player = ExoPlayer.Builder(instr.targetContext, tap.renderersFactory(instr.targetContext))
                .build().apply {
                    setVideoSurface(Surface(pg.filmSurfaceTexture))
                    setMediaItem(MediaItem.fromUri(filmUrl)); prepare(); playWhenReady = true
                }
        }

        // Wait for BOTH pictures and sound.
        // Wait for ENOUGH audio before judging it. The first run asserted on
        // ~10 buffers and saw peak=0.005 — the film's fade-in, not a broken
        // tap. Judging a soundtrack on its first fraction of a second is the
        // same error as judging a publisher on its first 80 messages (§6.2a).
        var n = 0
        while (n < 700 && (pg.framesAvailable.get() < 5 || tap.buffersSeen.get() < 120)) {
            draw(gl, pg, n, fps); enc.drain { _, _, _ -> }; n++; Thread.sleep(25)
        }
        assertTrue("no video frames (${pg.framesAvailable.get()})", pg.framesAvailable.get() >= 5)
        assertTrue("the audio tap saw nothing (${tap.buffersSeen.get()} buffers)",
                   tap.buffersSeen.get() >= 120)
        // A correctly plumbed silence is the failure this catches.
        assertTrue("the tap heard only silence — peak=${tap.peak}", tap.peak > 0.02f)
        // The film's rate is WHATEVER THE FILM HAS — this one is 48 kHz, and
        // an earlier version of this line asserted 44.1 because that is what
        // the Apple side happens to mix at. The engine must follow the source:
        // the AAC encoder is built from `tap.sampleRate`, and the
        // AudioSpecificConfig it produces then describes the frames actually
        // sent, which is the §6.2a rule.
        assertTrue("implausible sample rate ${tap.sampleRate}",
                   tap.sampleRate in 8000..192000)
        assertTrue("implausible channel count ${tap.channelCount}",
                   tap.channelCount in 1..8)

        val aac = StudioAacEncoder(tap.sampleRate, tap.channelCount); aac.start()
        tap.onPcm = { pcm, _, _ -> aac.encode(pcm) }
        var guard = 0
        while ((enc.avcC == null || aac.asc == null) && guard < 200) {
            draw(gl, pg, n + guard, fps)
            enc.drain { _, _, _ -> }; aac.drain { _, _ -> }
            guard++; Thread.sleep(10)
        }
        assertNotNull("no avcC", enc.avcC)
        assertNotNull("no AudioSpecificConfig — an ADTS-configured encoder has no csd-0", aac.asc)

        val p = RtmpPublisher()
        p.publish("rtmp://$host:$port/live", "androidaudio",
            RtmpStreamConfig(w, h, fps.toDouble(), 4_000_000, enc.avcC!!,
                             tap.sampleRate, tap.channelCount, 128_000, aac.asc!!))
        enc.requestKeyframe()

        var frame = n + 250
        val deadline = System.currentTimeMillis() + 25_000
        while (System.currentTimeMillis() < deadline) {
            draw(gl, pg, frame, fps)
            enc.drain { a, k, t -> p.sendVideo(a, k, t, t) }
            aac.drain { a, t -> p.sendAudio(a, t) }
            frame++; Thread.sleep(25)
        }
        enc.drain { a, k, t -> p.sendVideo(a, k, t, t) }
        aac.drain { a, t -> p.sendAudio(a, t) }

        val report = "video=${p.health.videoFramesSent} peak=${tap.peak} " +
                     "pcmBuffers=${tap.buffersSeen.get()} rate=${tap.sampleRate} " +
                     "ch=${tap.channelCount} state=${p.health.state}"
        assertTrue("almost nothing was encoded — $report", p.health.videoFramesSent > 20)
        assertEquals("the connection did not survive — $report", "publishing", p.health.state)
        Thread.sleep(1500)
        p.close()
        instr.runOnMainSync { player?.release() }
        aac.stop(); pg.tearDown(); gl.tearDown(); enc.stop()
    }

    private fun draw(gl: StudioGl, pg: StudioProgramGl, n: Int, fps: Int) {
        gl.makeCurrent()
        pg.updateFilmFrame()
        gl.clear(0f, 0f, 0f)
        pg.drawFilm(4f / 3f)
        gl.swap(n.toLong() * 1_000_000_000L / fps)
    }
}
