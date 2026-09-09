package app.archivewatch.android

import app.archivewatch.android.data.CatalogDatabase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * A corrupt downloaded catalog was the app's second-largest crash cluster:
 * `SQLException: Error code: 11, message: database disk image is malformed`,
 * thrown out of a coroutine with nothing above it to catch it.
 *
 * The open-probe reads `meta.itemCount`, which lives near the START of the
 * file, so a download torn further in opens cleanly and throws on the first
 * real query. These cases pin the two halves of the guard: recognising the
 * fault from SQLite's own words, and never mistaking an ordinary failure — or
 * a film whose title happens to contain the word — for it.
 */
class CatalogCorruptionTest {

    @Before
    fun reset() = CatalogDatabase.resetCorruptionReportingForTest()

    private fun corrupt(m: String) = assertTrue(m, CatalogDatabase.isCorruption(Exception(m)))
    private fun notCorrupt(m: String) = assertFalse(m, CatalogDatabase.isCorruption(Exception(m)))

    @Test
    fun `SQLite's own wording is recognised`() {
        corrupt("Error code: 11, message: database disk image is malformed")
        corrupt("file is not a database")
        corrupt("file is encrypted or is not a database")
    }

    @Test
    fun `an ordinary query failure is not corruption`() {
        notCorrupt("no such column: i.nope")
        notCorrupt("database is locked")
        notCorrupt("disk I/O error")
        notCorrupt("out of memory")
    }

    @Test
    fun `a film whose text contains the word is not corruption`() {
        // "Corruption" (1968) is a real film, and its title reaches error
        // messages through bound parameters. Matching the bare word would take
        // the catalog down over a search result.
        notCorrupt("no such table: Corruption")
        notCorrupt("UNIQUE constraint failed on 'The Corrupt Ones'")
    }

    @Test
    fun `a wrapped cause is found`() {
        val inner = Exception("Error code: 11, message: database disk image is malformed")
        assertTrue(CatalogDatabase.isCorruption(RuntimeException("query failed", inner)))
    }

    @Test
    fun `a cycle in the cause chain does not hang`() {
        val a = RuntimeException("outer")
        val b = RuntimeException("inner", a)
        assertFalse(CatalogDatabase.isCorruption(b))
    }

    @Test
    fun `the handler fires once per process, not once per query`() {
        var fired = 0
        CatalogDatabase.onCorruption = { fired += 1 }
        try {
            // Simulate what queryRaw does on each of many reads after one bad file.
            repeat(25) {
                if (CatalogDatabase.isCorruption(Exception("database disk image is malformed"))) {
                    CatalogDatabase.reportCorruptionForTest(Exception("x"))
                }
            }
            assertEquals(1, fired)
        } finally {
            CatalogDatabase.onCorruption = null
        }
    }
}
