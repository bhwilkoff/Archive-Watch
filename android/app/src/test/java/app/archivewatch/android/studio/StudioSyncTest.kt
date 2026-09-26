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

    @Test fun `run state is applied at once and a paused guest is on the host's frame`() {
        assertEquals(
            StudioSync.Correction.SetPaused(true),
            StudioSync.correction(130.0, false, paused, 1030.0),
        )
        assertEquals(
            "a paused guest on the wrong frame is moved to the host's",
            StudioSync.Correction.Seek(100.0),
            StudioSync.correction(104.7, true, paused, 1030.0),
        )
        assertEquals(
            "one within tolerance is left alone",
            StudioSync.Correction.None,
            StudioSync.correction(100.1, true, paused, 1030.0),
        )
    }

    @Test fun `backoff`() {
        assertEquals(StudioSync.POLL_FAST_SECONDS, StudioSync.pollInterval(5.0), 1e-9)
        assertEquals(StudioSync.POLL_IDLE_SECONDS, StudioSync.pollInterval(120.0), 1e-9)
        assertTrue(StudioSync.POLL_IDLE_SECONDS > StudioSync.POLL_FAST_SECONDS)
    }

    // THE HOST'S COPY (2026-09-26): the Worker's and Apple's table again.
    @Test fun `a room copy becomes an archive dot org URL and nothing else`() {
        assertEquals("https://archive.org/download/the-scarecrow/The%20Scarecrow.mp4",
            StudioRoomCopy.urlFromPath("the-scarecrow/The Scarecrow.mp4"))
        assertEquals("https://archive.org/download/reels/r/reel1.mov",
            StudioRoomCopy.urlFromPath("reels/r/reel1.mov"))
        for (bad in listOf("https://evil.example/x.mp4", "//evil.example/x.mp4", "a/../b.mp4",
                           "the-scarecrow", "the-scarecrow/", "bad item!/x.mp4", "a/b\u0000.mp4")) {
            assertEquals("refused: $bad", null, StudioRoomCopy.urlFromPath(bad))
        }
    }

    @Test fun `in a room the HOST chooses, and outside one nothing is overridden`() {
        val fallback = "https://archive.org/download/TheScarecrow1920/default.mp4"
        StudioRoomCopy.clear()
        assertEquals(null, StudioRoomCopy.url("TheScarecrow1920", fallback))
        StudioRoomCopy.set("TheScarecrow1920", "the-scarecrow/The Scarecrow.mp4")
        assertEquals("https://archive.org/download/the-scarecrow/The%20Scarecrow.mp4",
            StudioRoomCopy.url("TheScarecrow1920", fallback))
        assertEquals(null, StudioRoomCopy.url("Metropolis", fallback))
        StudioRoomCopy.set("TheScarecrow1920", null)
        assertEquals("an older host plays the DEFAULT, not the viewer's choice",
            fallback, StudioRoomCopy.url("TheScarecrow1920", fallback))
        StudioRoomCopy.clear()
    }
}
