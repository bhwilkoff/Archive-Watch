package app.archivewatch.android.studio

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** SHAREPLAY §11.6.1a on Android: which pauses and seeks are the GUEST's. */
class StudioGuestMoveTest {
    @Test fun `a guest's own move is recognized`() {
        assertTrue(StudioSyncFollower.isGuestMove(5_000, false, 3_600_000, 1_000_000))
    }

    @Test fun `our own seek or pause is not the guest's`() {
        assertFalse(StudioSyncFollower.isGuestMove(400, false, 3_600_000, 1_000_000))
    }

    @Test fun `a host pause is not the guest's`() {
        assertFalse(StudioSyncFollower.isGuestMove(5_000, true, 3_600_000, 1_000_000))
    }

    @Test fun `the film ending is not the guest's`() {
        assertFalse(StudioSyncFollower.isGuestMove(5_000, false, 3_600_000, 3_599_500))
    }
}
