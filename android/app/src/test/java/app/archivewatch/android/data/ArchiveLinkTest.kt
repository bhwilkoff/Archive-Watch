package app.archivewatch.android.data

import org.junit.Assert.assertEquals
import org.junit.Test

/** A pasted archive.org link resolves in search (2026-09-26) — the same table
 *  as the web's tools/test_web_archive_address.mjs and Apple's CatalogDB. */
class ArchiveLinkTest {
    private fun id(t: String) = CatalogDatabase.archiveIdFromLink(t)

    @Test fun `every archive_org address shape gives the identifier`() {
        assertEquals("TheScarecrow1920", id("https://archive.org/details/TheScarecrow1920"))
        assertEquals("the-scarecrow", id("archive.org/details/the-scarecrow/The+Scarecrow.mp4"))
        assertEquals("the-scarecrow", id("https://archive.org/download/the-scarecrow/The%20Scarecrow.mp4"))
        assertEquals("x-y", id("https://www.archivewatch.org/details/x-y?q=1"))
        assertEquals("abc", id("  https://archive.org/embed/abc  "))
    }

    @Test fun `anything else is not a link`() {
        assertEquals(null, id("scarecrow"))
        assertEquals(null, id("https://evil.example/details/x"))
        assertEquals(null, id("archive.org"))
    }
}
