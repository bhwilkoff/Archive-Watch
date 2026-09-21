package app.archivewatch.android

import app.archivewatch.android.studio.CameraStallRecovery
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The same nine cases §8.23 asserts on the Swift side. */
class StudioCameraStallTest {
    private fun r() = CameraStallRecovery()

    @Test fun `a camera delivering frames is never rebuilt`() {
        val s = r()
        repeat(30) { assertFalse(s.tick(true, 900L, 30, true)) }
    }

    @Test fun `three dead ticks are tolerated and the fourth recovers`() {
        val s = r()
        assertFalse(s.tick(true, 900L, 0, true))
        assertFalse(s.tick(true, 900L, 0, true))
        assertFalse(s.tick(true, 900L, 0, true))
        assertTrue(s.tick(true, 900L, 0, true))
    }

    @Test fun `at most three attempts in a show`() {
        val s = r()
        var n = 0
        repeat(100) { if (s.tick(true, 900L, 0, true)) n++ }
        assertEquals(3, n)
    }

    // CONTROL: a camera that never started is a different problem. Without
    // this, every television — which has no camera — rebuilds three times a show.
    @Test fun `CONTROL a camera that never started is not rebuilt`() {
        val s = r()
        repeat(40) { assertFalse(s.tick(true, 0L, 0, true)) }
    }

    @Test fun `CONTROL an off-air show is not rebuilt`() {
        val s = r()
        repeat(40) { assertFalse(s.tick(true, 900L, 0, false)) }
    }

    @Test fun `CONTROL no camera attached is not rebuilt`() {
        val s = r()
        repeat(40) { assertFalse(s.tick(false, 0L, 0, true)) }
    }

    @Test fun `recovered frames reset the grace period`() {
        val s = r()
        s.tick(true, 900L, 0, true)
        s.tick(true, 900L, 0, true)
        s.tick(true, 930L, 30, true)
        repeat(3) { assertFalse(s.tick(true, 930L, 0, true)) }
    }

    @Test fun `a new show gets a fresh budget`() {
        val s = r()
        repeat(100) { s.tick(true, 900L, 0, true) }
        s.reset()
        var n = 0
        repeat(100) { if (s.tick(true, 900L, 0, true)) n++ }
        assertEquals(3, n)
    }
}
