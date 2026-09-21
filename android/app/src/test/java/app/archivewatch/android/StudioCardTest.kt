package app.archivewatch.android

import app.archivewatch.android.studio.StudioCard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The words must be APPLE's words. A card is the one overlay an audience reads
 * in full, so two platforms wording it differently is a parity bug the viewer
 * sees rather than the developer.
 */
class StudioCardTest {
    @Test fun `headlines match the Apple renderer`() {
        assertEquals("Starting soon", StudioCard.StartingSoon(60).headline)
        assertEquals("Intermission", StudioCard.Intermission.headline)
        assertEquals("Thanks for watching", StudioCard.Ending.headline)
    }

    @Test fun `details match the Apple renderer`() {
        assertEquals("1:00", StudioCard.StartingSoon(60).detail)
        assertEquals("0:05", StudioCard.StartingSoon(5).detail)
        assertEquals("any moment now", StudioCard.StartingSoon(0).detail)
        assertEquals("back shortly", StudioCard.Intermission.detail)
        assertEquals("archivewatch.org", StudioCard.Ending.detail)
    }

    // §2.1: a viewer arriving at a countdown should learn what they are about
    // to watch. Not on the ending card, where the film is over.
    @Test fun `the film is named on every card but the ending`() {
        assertTrue(StudioCard.StartingSoon(30).showsFilm)
        assertTrue(StudioCard.Intermission.showsFilm)
        assertFalse(StudioCard.Ending.showsFilm)
    }

    @Test fun `the clock pads seconds`() {
        assertEquals("2:03", StudioCard.clock(123))
        assertEquals("0:00", StudioCard.clock(0))
        assertEquals("10:00", StudioCard.clock(600))
    }
}
