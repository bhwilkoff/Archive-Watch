package app.archivewatch.android.data

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Decision 166: one episode of a series held as files of one archive.org item. */
class BundleEpisodeTest {
    @Test fun `the real item is everything before the first at sign`() {
        assertEquals("UFO.complete", archiveItemOf("UFO.complete@e01"))
        assertEquals("X", archiveItemOf("X@s2e05"))
        assertEquals("X", archiveItemOf("X@x-some@extra"))
        assertEquals("TheScarecrow1920", archiveItemOf("TheScarecrow1920"))
        assertTrue("UFO.complete@e01".isBundleFile)
        assertFalse("TheScarecrow1920".isBundleFile)
    }

    @Test fun `archive pages use the real item`() {
        val url = "https://archive.org/download/UFO.complete/UFO.01.Identified.mp4"
        assertEquals("UFO.01.Identified.mp4", archiveFileOf(url))
        assertEquals(
            "https://archive.org/details/UFO.complete/UFO.01.Identified.mp4",
            archiveDetailsURL("UFO.complete@e01", url),
        )
        assertEquals(
            "https://archive.org/details/TheScarecrow1920",
            archiveDetailsURL("TheScarecrow1920", "https://archive.org/download/TheScarecrow1920/a.mp4"),
        )
        assertEquals(
            "https://archive.org/services/img/UFO.complete",
            CatalogItem(archiveID = "UFO.complete@e01").archiveThumb,
        )
    }

    private fun f(name: String, original: String? = null) = JSONObject().apply {
        put("name", name)
        put("size", "90000000")
        put("format", if (original == null) "MPEG4" else "h.264")
        put("source", if (original == null) "original" else "derivative")
        if (original != null) put("original", original)
    }

    private val files = JSONArray().apply {
        put(f("UFO.01.Identified.mp4"))
        put(f("UFO.01.Identified.ia.mp4", original = "UFO.01.Identified.mp4"))
        put(f("UFO.02.Computer Affair.mp4"))
        put(f("UFO.02.Computer Affair.ia.mp4", original = "UFO.02.Computer Affair.mp4"))
    }

    @Test fun `a bundle episode offers only its own file and its derivatives`() {
        val names = ArchiveVersions.parse("UFO.complete", files, "UFO.01.Identified.mp4").map { it.name }
        assertEquals(setOf("UFO.01.Identified.mp4", "UFO.01.Identified.ia.mp4"), names.toSet())
        // The same family is found from the derivative's side.
        val fromDerivative = ArchiveVersions.parse("UFO.complete", files, "UFO.01.Identified.ia.mp4").map { it.name }
        assertEquals(names.toSet(), fromDerivative.toSet())
        // Control: a whole item keeps every file.
        assertEquals(4, ArchiveVersions.parse("UFO.complete", files, null).size)
    }

    @Test fun `a saved choice on a bundle episode plays from the real item`() {
        assertEquals(
            "UFO.complete" to "UFO.01.Identified.ia.mp4",
            ArchiveVersions.location("UFO.01.Identified.ia.mp4", "UFO.complete@e01"),
        )
    }
}
