package app.archivewatch.android

import android.graphics.ImageFormat
import android.media.ImageReader
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.archivewatch.android.studio.StudioEngine
import app.archivewatch.android.studio.StudioOverlayBitmap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * WHAT DOES THE SECOND PASS COST? (docs/WATCH-TOGETHER.md §6.2k)
 *
 * The Google TV showed 11 fps at 43.5 ms per frame once the engine began
 * drawing the program twice — encoder surface and host screen. That is over
 * the 33.3 ms budget, and "the dongle or the dual pass?" is not answerable by
 * looking at one number.
 *
 * So: the SAME device, the same film, the same program, run twice — once with
 * a display surface attached and once without. A controlled experiment beats a
 * correlation (Decision 075), and this one needs no second device.
 *
 * The display is an `ImageReader` at 1920×1080 rather than a real window: it
 * is a real consumer of a real size, and what is under test is the cost of
 * COMPOSING and swapping a second surface, not of a compositor putting it on
 * a panel.
 */
@UnstableApi
@RunWith(AndroidJUnit4::class)
class StudioRenderCostTest {

    private val args = InstrumentationRegistry.getArguments()
    private val filmUrl = args.getString("filmUrl")
        ?: "https://dn600307.us.archive.org/0/items/PreviewTheKissOfDeath/preview%20-%20The%20Kiss%20of%20Death.mp4"
    private val seconds = (args.getString("costSeconds") ?: "20").toInt()

    private fun run(withDisplay: Boolean): Pair<Double, Long> = runBlocking {
        val engine = StudioEngine()
        engine.layoutShowsCamera = false
        engine.filmAspect = 4f / 3f
        val instr = InstrumentationRegistry.getInstrumentation()
        val scope = CoroutineScope(SupervisorJob())
        engine.start(
            scope = scope, destination = null,
            overlay = StudioOverlayBitmap.lowerThird(
                1280, 720, "The Kiss of Death", "1916 · Victor Sjöström",
                "Public domain — published 1916, before 1930"))

        var waited = 0
        while (engine.filmSurface == null && waited < 120) { Thread.sleep(50); waited++ }
        val reader = if (withDisplay) {
            ImageReader.newInstance(1920, 1080, ImageFormat.PRIVATE, 3).also {
                engine.setDisplaySurface(it.surface)
            }
        } else null

        var player: ExoPlayer? = null
        instr.runOnMainSync {
            player = ExoPlayer.Builder(instr.targetContext).build().apply {
                setVideoSurface(engine.filmSurface)
                setMediaItem(MediaItem.fromUri(filmUrl)); prepare(); playWhenReady = true
            }
        }
        Thread.sleep(seconds * 1000L)
        val h = engine.health
        engine.stop()
        instr.runOnMainSync { player?.release() }
        reader?.close()
        h.averageRenderMillis to h.programFramesRendered
    }

    @Test fun theSecondPassCosts() {
        // INTERLEAVED, AND THE FIRST RUN OF EACH IS DISCARDED.
        //
        // The first version ran one-pass then two-pass, reasoning that putting
        // the cheaper case first would avoid flattering it. It did the
        // opposite: the cold run took the warm-up and the result was
        // "encoder-only 57.1 ms, encoder+display 40.3 ms" — the two-pass case
        // apparently FASTER, which is not a finding, it is an ordering
        // artifact. Warm-up is a variable like any other and has to be
        // controlled rather than reasoned about.
        run(withDisplay = false)          // warm-up, discarded
        val (oneA, framesA) = run(withDisplay = false)
        val (twoA, framesB) = run(withDisplay = true)
        val (oneB, _) = run(withDisplay = false)
        val (twoB, _) = run(withDisplay = true)

        val one = (oneA + oneB) / 2
        val two = (twoA + twoB) / 2
        val report = ("encoder-only %.1f / %.1f (mean %.1f) ms | " +
                      "encoder+display %.1f / %.1f (mean %.1f) ms | second pass %+.1f ms")
            .format(oneA, oneB, one, twoA, twoB, two, two - one)
        android.util.Log.i("AWCOST", report)
        println(report)

        assertTrue("the one-pass run rendered almost nothing — $report", framesA > 50)
        assertTrue("the two-pass run rendered almost nothing — $report", framesB > 50)
        // No verdict on the NUMBERS here: this test exists to produce them,
        // and a threshold invented before the measurement is a guess wearing
        // an assertion's clothes. The numbers go in §6.2k.
        assertTrue(one > 0.0 && two > 0.0)
    }
}
