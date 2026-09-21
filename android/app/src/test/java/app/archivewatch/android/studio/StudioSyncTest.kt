package app.archivewatch.android.studio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * The Kotlin side of numbers that exist in three languages.
 *
 * Same cases as `tools/test_studio_sync.swift` (§8.27) and
 * `tools/test_together_web.mjs` (§8.32). A port is not a proof: the way this
 * breaks is that `expectedPosition` forgets to ask whether the film is PAUSED
 * and returns a perfectly plausible number that is wrong.
 */
class StudioSyncTest {

    private val playing = StudioSync.State("x", position = 100.0, atServerTime = 1000.0)
    private val paused = playing.copy(paused = true)

    @Test fun `a playing film advances with server time`() {
        assertEquals(130.0, playing.expectedPosition(1030.0), 1e-9)
        assertEquals(100.0, playing.expectedPosition(1000.0), 1e-9)
    }

    @Test fun `A PAUSED FILM DOES NOT ADVANCE`() {
        assertEquals(
            "an elapsed-time formula that forgets to ask returns 130",
            100.0, paused.expectedPosition(1030.0), 1e-9,
        )
    }

    @Test fun `a server time before the record does not rewind the film`() {
        assertEquals(100.0, playing.expectedPosition(990.0), 1e-9)
    }

    @Test fun `the clock keeps the FASTEST sample, and averaging is worse`() {
        // ASYMMETRIC delays, because under symmetric delay Cristian's
        // algorithm is exact at any round trip and a control built that way
        // cannot fail — which §8.27 discovered from a fixture of its own.
        val samples = listOf(
            StudioSync.ClockSample(0.0, 5.010, 0.020),   // out 10ms, back 10ms
            StudioSync.ClockSample(1.0, 6.700, 1.800),   // out 700ms, back 100ms
            StudioSync.ClockSample(2.0, 7.800, 3.000),   // out 800ms, back 200ms
        )
        val best = StudioSync.bestOffset(samples)!!
        assertEquals(0.020, best.roundTrip, 1e-9)
        assertTrue("within its own bound", abs(best.offset - 5.0) <= best.error)
        val averaged = samples.map { it.offset }.average()
        assertTrue(
            "averaging must be materially worse (min ${abs(best.offset - 5.0)}, avg ${abs(averaged - 5.0)})",
            abs(averaged - 5.0) > abs(best.offset - 5.0) && abs(averaged - 5.0) > 0.1,
        )
    }

    private fun corr(local: Double, localPaused: Boolean = false, now: Double = 1030.0) =
        StudioSync.correction(local, localPaused, playing, now)

    @Test fun `corrections match the other platforms`() {
        assertEquals(StudioSync.Correction.None, corr(130.05))
        assertEquals(StudioSync.Correction.Nudge(StudioSync.NUDGE_FAST), corr(129.0))
        assertEquals(StudioSync.Correction.Nudge(StudioSync.NUDGE_SLOW), corr(131.0))
        assertEquals(StudioSync.Correction.Seek(130.0), corr(120.0))
        // CONTROL: behind and ahead must DIFFER, or a sign error passes both.
        assertTrue(corr(129.0) != corr(131.0))
    }

    @Test fun `run state is applied at once and a paused film is never seeked`() {
        assertEquals(
            StudioSync.Correction.SetPaused(true),
            StudioSync.correction(130.0, false, paused, 1030.0),
        )
        assertEquals(
            "a paused film cannot drift, however large the gap",
            StudioSync.Correction.None,
            StudioSync.correction(10.0, true, paused, 1030.0),
        )
    }

    @Test fun `backoff`() {
        assertEquals(StudioSync.POLL_FAST_SECONDS, StudioSync.pollInterval(5.0), 1e-9)
        assertEquals(StudioSync.POLL_IDLE_SECONDS, StudioSync.pollInterval(120.0), 1e-9)
        assertTrue(StudioSync.POLL_IDLE_SECONDS > StudioSync.POLL_FAST_SECONDS)
    }
}
