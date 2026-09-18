package app.archivewatch.android

import app.archivewatch.android.studio.RtmpHealth
import app.archivewatch.android.studio.StudioHealth
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * WATCH-TOGETHER §5: "never auto-lower quality silently — an adaptive-bitrate
 * step is shown as it happens."
 *
 * `qualityNote` was written by both engines and rendered by NOTHING on either
 * platform until 2026-09-17: the only reader anywhere was a diagnostic log
 * line. So the sentence existed, was correct, and no host could see it — and a
 * run that read it out of a log was mistaken for proof that §5 was satisfied.
 *
 * `problem` is the one surface hook on Android (the §9.4 readout and the §9.3
 * sheet both render it), and it is pure logic, so it can be checked here
 * rather than photographed.
 */
class StudioProblemTest {

    private fun live(note: String? = null, dropped: Long = 0) = StudioHealth(
        isRunning = true,
        filmFramesPerSecond = 30,
        encodedFramesPerSecond = 30,
        hasDestination = true,
        qualityNote = note,
        publisher = RtmpHealth(state = "publishing", videoFramesDropped = dropped))

    @Test fun `a live show with no note reports no problem`() {
        assertEquals("LIVE", live().showState)
        assertEquals(null, live().problem)
    }

    @Test fun `the adaptive step is what the host is told`() {
        val note = "The device is running hot, so the picture is being sent at 2400 kbps instead of 4000 kbps."
        assertEquals(note, live(note = note).problem)
    }

    @Test fun `the restore announcement is shown too`() {
        // §6.5: "a step back up the host cannot see is the same defect as a
        // step down they cannot see."
        val note = "Back to full quality 4000 kbps."
        assertEquals(note, live(note = note).problem)
    }

    @Test fun `a note does not mask a show that stopped encoding`() {
        // The note is preferred over a STATE LABEL, never over a fault: a
        // frozen picture matters more than a bitrate step, and showState
        // still reports STOPPED for the capsule beside it.
        val stalled = StudioHealth(
            isRunning = true, filmFramesPerSecond = 30, encodedFramesPerSecond = 0,
            hasDestination = true, qualityNote = "Back to full quality 4000 kbps.",
            publisher = RtmpHealth(state = "publishing"))
        assertEquals("STOPPED", stalled.showState)
    }
}
