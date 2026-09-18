package app.archivewatch.android

import app.archivewatch.android.studio.StudioRights
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The gate that decides whether a film may be broadcast to a real person's
 * channel (docs/WATCH-TOGETHER.md §3.4). Its sentences are checked against the
 * Apple copy by `tools/test_studio_rights_parity.py`; what is checked HERE is
 * the decision itself.
 */
class StudioRightsTest {

    @Test fun `a pre-1930 age-cleared film may go live`() {
        assertNull(StudioRights.refusal("safe_pd_age", "feature-film", 1916))
        assertTrue(StudioRights.canGoLive("safe_pd_age", "silent-film", 1929))
    }

    @Test fun `an unknown verdict REFUSES`() {
        // The schema-1 case: a cached catalog with no rightsBucket column.
        // Refusing is the whole rule — the alternative is broadcasting a film
        // whose rights nobody could read.
        assertNotNull(StudioRights.refusal(null, "feature-film", 1916))
        assertNotNull(StudioRights.refusal("", "feature-film", 1916))
        assertFalse(StudioRights.canGoLive(null, "feature-film", 1916))
    }

    @Test fun `age-cleared without a supporting year REFUSES`() {
        // A bucket computed from a release date the item no longer carries.
        assertNotNull(StudioRights.refusal("safe_pd_age", "feature-film", null))
        assertNotNull(StudioRights.refusal("safe_pd_age", "feature-film", 1954))
    }

    @Test fun `television and commercials are never broadcast whatever their rights say`() {
        for (type in listOf("tv-series", "tv-episode", "tv-special", "commercial")) {
            assertNotNull("$type must refuse",
                          StudioRights.refusal("safe_pd_age", type, 1916))
        }
    }

    @Test fun `the guaranteed tier refuses everything but age`() {
        for (bucket in listOf("safe_gov", "safe_cc", "safe_archive_license", "presumed_pd")) {
            assertNotNull("$bucket must refuse at the guaranteed tier",
                          StudioRights.refusal(bucket, "feature-film", 1916))
        }
    }

    @Test fun `the strict tier is wider but still refuses unproven claims`() {
        assertNull(StudioRights.refusal("safe_gov", "feature-film", 1952,
                                        StudioRights.Tier.STRICT))
        assertNotNull(StudioRights.refusal("presumed_pd", "feature-film", 1952,
                                           StudioRights.Tier.STRICT))
    }

    @Test fun `every refusal is a sentence a person can read`() {
        val buckets = listOf(
            "safe_gov", "safe_cc", "safe_archive_license", "presumed_pd",
            "renewal_zone", "renewal_zone_bw", "renewal_zone_footprint",
            "renewal_zone_commercial", "renewed_copyright_classic",
            "modern_copyright", "modern_copyright_unconfirmed",
            "modern_copyright_confirmed", "modern_noyear_risk", "no_evidence",
            "unknown_year", "uploader_cannot_dedicate", "wrongmatch_bw",
            "wrongmatch_title", "wrongmatch_idyear", "uploader_copyright_claim",
            "commercial_keep", "commercial_slop", "commercial_modern_risk",
            "copyrighted_trailer", "excerpt",
        )
        for (b in buckets) {
            val why = StudioRights.explain(b)
            assertTrue("$b has no real sentence", why.length > 40)
            assertTrue("$b does not end in a full stop: $why", why.trimEnd().endsWith("."))
            // The defect that reached a user once: an internal bucket name
            // printed at a viewer because no sentence existed.
            assertFalse("$b LEAKS its internal name to the viewer: $why", why.contains(b))
        }
    }

    @Test fun `the policy sentence explains the rule itself`() {
        assertTrue(StudioRights.policy.contains("1930"))
        assertEquals(StudioRights.Tier.GUARANTEED, StudioRights.tier)
    }
}
