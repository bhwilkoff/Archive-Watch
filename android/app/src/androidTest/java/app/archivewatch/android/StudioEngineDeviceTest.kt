package app.archivewatch.android

import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.archivewatch.android.studio.StudioEngine
import app.archivewatch.android.studio.StudioFilmAudioTap
import app.archivewatch.android.studio.StudioOverlayBitmap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.InetSocketAddress
import java.net.Socket

/**
 * The ASSEMBLED engine (ANDROID-DESIGN §9.1): one render loop driving film,
 * overlay, both encoders and the publisher, reporting health once a second.
 *
 * Each piece under it was proved separately on hardware (§6.2b–e). What is new
 * here is that they run TOGETHER on one thread with one clock — which is
 * exactly the kind of thing that works in pieces and deadlocks assembled.
 */
@UnstableApi
@RunWith(AndroidJUnit4::class)
class StudioEngineDeviceTest {

    private val args = InstrumentationRegistry.getArguments()
    private val host: String = args.getString("rtmpHost") ?: "10.0.0.90"
    private val port = 19351
    private val filmUrl = args.getString("filmUrl")
        ?: "https://archive.org/download/Popeye_forPresident/Popeye_forPresident_512kb.mp4"

    private fun serverIsUp(): Boolean = try {
        Socket().use { it.connect(InetSocketAddress(host, port), 1500); true }
    } catch (_: Exception) { false }

    @Test fun theEngineRunsTheWholeShow() = runBlocking {
        assumeTrue("no RTMP server at $host:$port — skipping", serverIsUp())

        val engine = StudioEngine()
        engine.layoutShowsCamera = false     // no camera on a television (§9.6)
        engine.filmAspect = 4f / 3f
        val tap = StudioFilmAudioTap()
        val instr = InstrumentationRegistry.getInstrumentation()
        val scope = CoroutineScope(SupervisorJob())

        engine.start(
            scope = scope,
            destination = "rtmp://$host:$port/live",
            streamKey = "androidengine",
            audioTap = tap,
            overlay = StudioOverlayBitmap.lowerThird(
                1280, 720, "Popeye for President", "1956 · Seymour Kneitel",
                "Public domain — no renewal on record"))

        // The engine builds its surfaces on its own thread; give it a moment
        // before the player can be pointed at one.
        var waited = 0
        while (engine.filmSurface == null && waited < 100) { Thread.sleep(50); waited++ }
        val surface = engine.filmSurface
        assertTrue("the engine never produced a film surface", surface != null)

        var player: ExoPlayer? = null
        instr.runOnMainSync {
            player = ExoPlayer.Builder(instr.targetContext, tap.renderersFactory(instr.targetContext))
                .build().apply {
                    setVideoSurface(surface)
                    setMediaItem(MediaItem.fromUri(filmUrl)); prepare(); playWhenReady = true
                }
        }

        // Let it run, then read the engine's OWN health rather than any
        // counter this test keeps.
        Thread.sleep(35_000)
        val h = engine.health
        val report = "state=${h.showState} rendered=${h.programFramesRendered} " +
                     "encoded=${h.programFramesEncoded} filmFps=${h.filmFramesPerSecond} " +
                     "encFps=${h.encodedFramesPerSecond} render=${h.averageRenderMillis}ms " +
                     "pub=${h.publisher.state} problem=${h.problem}"

        assertTrue("the engine never reported running — $report", h.isRunning)
        assertTrue("nothing was rendered — $report", h.programFramesRendered > 100)
        assertTrue("nothing was encoded — $report", h.programFramesEncoded > 20)
        assertTrue("the film stopped arriving — $report", h.filmFramesPerSecond > 0)
        // The show's own verdict, not the transport's — a destination was
        // given, so anything but LIVE means the broadcast is not happening.
        assertEquals("the show is not live — $report", "LIVE", h.showState)
        assertEquals("a live show should report no problem — $report", null, h.problem)

        engine.stop()
        instr.runOnMainSync { player?.release() }
        assertEquals("health should reset after stop", false, engine.health.isRunning)
    }
}
