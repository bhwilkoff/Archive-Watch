package app.archivewatch.android

import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.resolveListRows
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * A shared playlist naming two ids that forward to one survivor drew the same
 * key twice in a LazyVerticalGrid, which Compose throws on. The rows must be
 * unique by card, and the "N of M — K no longer in the catalog" line must count
 * the ids that resolved to nothing, not the gap the dedup made.
 */
class SharedListRowsTest {
    private val s = CatalogItem("survivor", title = "S")
    private val b = CatalogItem("b", title = "B")

    @Test
    fun `two ids forwarding to one card show it once and count nothing missing`() {
        val keyed = mapOf("old1" to s, "old2" to s, "b" to b)
        val r = resolveListRows(listOf("old1", "b", "old2"), keyed)
        assertEquals(listOf("survivor", "b"), r.rows.map { it.archiveID })
        assertEquals(0, r.missing)
    }

    @Test
    fun `an id that resolves to nothing is counted missing`() {
        val r = resolveListRows(listOf("b", "gone"), mapOf("b" to b))
        assertEquals(listOf("b"), r.rows.map { it.archiveID })
        assertEquals(1, r.missing)
    }

    @Test
    fun `control - distinct ids keep their order and count no gap`() {
        val keyed = mapOf("survivor" to s, "b" to b)
        val r = resolveListRows(listOf("b", "survivor"), keyed)
        assertEquals(listOf("b", "survivor"), r.rows.map { it.archiveID })
        assertEquals(0, r.missing)
    }
}
