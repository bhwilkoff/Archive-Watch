package app.archivewatch.android

import androidx.media3.exoplayer.Renderer
import app.archivewatch.android.player.AudioSyncOffset
import app.archivewatch.android.player.AudioSyncVideoRenderer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.lang.reflect.Proxy

class AudioSyncTest {

    /** A Renderer that records the position each call was given. */
    private class Recorder {
        val calls = mutableListOf<Pair<String, Long>>()
        val renderer = Proxy.newProxyInstance(
            Renderer::class.java.classLoader, arrayOf(Renderer::class.java),
        ) { _, m, args ->
            val first = args?.firstOrNull()
            if (first is Long) calls += m.name to first
            when (m.returnType) {
                java.lang.Long.TYPE -> 0L
                java.lang.Boolean.TYPE -> false
                java.lang.Integer.TYPE -> 0
                else -> null
            }
        } as Renderer
    }

    @Test fun stepsAndLimits() {
        val o = AudioSyncOffset()
        assertEquals(0, o.offsetMs)
        o.nudge(3); assertEquals(300, o.offsetMs)
        o.nudge(-5); assertEquals(-200, o.offsetMs)
        o.set(9_999); assertEquals(2_000, o.offsetMs)
        o.nudge(1); assertEquals(2_000, o.offsetMs)
        o.set(-9_999); assertEquals(-2_000, o.offsetMs)
        o.set(149); assertEquals(100, o.offsetMs)      // snapped to a 100 ms step
        o.reset(); assertEquals(0, o.offsetMs)
    }

    @Test fun plusMeansTheSoundComesLater() {
        // The clock is the audio's playout position. At +1000 the video is asked
        // for the frame one second AHEAD of the sound, so the sound is later.
        assertEquals(11_000_000L, AudioSyncOffset.videoPositionUs(10_000_000L, 1_000))
        assertEquals(9_000_000L, AudioSyncOffset.videoPositionUs(10_000_000L, -1_000))
        assertEquals(10_000_000L, AudioSyncOffset.videoPositionUs(10_000_000L, 0))
    }

    @Test fun labels() {
        assertEquals("0 s", AudioSyncOffset.label(0))
        assertEquals("+0.3 s", AudioSyncOffset.label(300))
        assertEquals("-1.2 s", AudioSyncOffset.label(-1_200))
        assertEquals("+2.0 s", AudioSyncOffset.label(2_000))
    }

    @Test fun onlyTheVideoRenderIsShiftedNeverTheTruePosition() {
        val rec = Recorder()
        val o = AudioSyncOffset().apply { set(1_000) }
        val r = AudioSyncVideoRenderer(rec.renderer, o)
        r.render(5_000_000L, 0L)
        r.getDurationToProgressUs(5_000_000L, 0L)
        // A seek lands on the true position; the shift must not move it.
        r.resetPosition(5_000_000L, false)
        assertEquals(
            listOf("render" to 6_000_000L, "getDurationToProgressUs" to 6_000_000L,
                   "resetPosition" to 5_000_000L),
            rec.calls,
        )
        // The player's position (what the scrubber shows and history saves) is
        // the audio renderer's clock; a video renderer offers none to replace it.
        assertNull(r.mediaClock)
    }

    @Test fun zeroIsAPassThrough() {
        val rec = Recorder()
        val r = AudioSyncVideoRenderer(rec.renderer, AudioSyncOffset())
        r.render(7_000_000L, 0L)
        assertEquals(listOf("render" to 7_000_000L), rec.calls)
    }
}
