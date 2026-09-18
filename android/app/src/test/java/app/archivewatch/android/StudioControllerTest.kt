package app.archivewatch.android

import androidx.media3.common.util.UnstableApi
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.studio.StudioController
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the Detail entry DECIDES (ANDROID-DESIGN §9.2) — not what it looks
 * like. The appearance of a phone surface needs a phone; this is the branch
 * that sends a host to the player or stops them with a sentence, and getting
 * it wrong is how someone broadcasts a film they should not.
 */
@UnstableApi
class StudioControllerTest {

    @After fun clear() {
        StudioController.refusal = null
        StudioController.disarm()
    }

    private fun item(
        id: String = "film1",
        bucket: String? = "safe_pd_age",
        type: String = "feature-film",
        year: Int? = 1916,
    ) = CatalogItem(archiveID = id, title = "A Film", year = year,
                    contentType = type, rightsBucket = bucket, director = "Someone")

    @Test fun `an eligible film arms and sends the host to the player`() {
        assertTrue(StudioController.arm(item()))
        assertEquals("film1", StudioController.armedFilmID)
        assertNull("an armed film must not also set a refusal", StudioController.refusal)
        assertEquals("1916 · Someone", StudioController.armedSubtitle)
        assertNotNull("an age-cleared film carries its provenance line",
                      StudioController.armedProvenance)
    }

    @Test fun `a refused film does NOT arm, and says why`() {
        assertFalse(StudioController.arm(item(bucket = "presumed_pd")))
        assertNull("a refused film must never be armed", StudioController.armedFilmID)
        val why = StudioController.refusal
        assertNotNull(why)
        // The sentence is the point: a greyed-out row teaches nothing.
        assertTrue("the refusal must be a readable sentence: $why", (why?.length ?: 0) > 40)
        assertFalse("the refusal must not leak the bucket name: $why",
                    why!!.contains("presumed_pd"))
    }

    @Test fun `a missing rights verdict refuses — the schema-1 case`() {
        assertFalse(StudioController.arm(item(bucket = null)))
        assertNotNull(StudioController.refusal)
    }

    @Test fun `television refuses whatever its rights say`() {
        assertFalse(StudioController.arm(item(bucket = "safe_pd_age", type = "tv-episode")))
        assertNotNull(StudioController.refusal)
    }

    @Test fun `an age claim with no supporting year refuses`() {
        assertFalse(StudioController.arm(item(year = null)))
        assertNotNull(StudioController.refusal)
    }

    @Test fun `the audio tap is only handed to the film that was armed`() {
        assertTrue(StudioController.arm(item(id = "armed")))
        assertNull("another film must not get the armed film's tap",
                   StudioController.audioTapFor("someone-else"))
        assertNotNull(StudioController.audioTapFor("armed"))
    }

    @Test fun `a film with no provenance still arms`() {
        // `strict` buckets carry no age line; the lower third simply omits it
        // rather than inventing one.
        assertTrue(StudioController.arm(item(bucket = "safe_pd_age", year = 1920)))
        assertNotNull(StudioController.armedProvenance)
        StudioController.disarm()
        assertNull(StudioController.armedFilmID)
    }
}
