package app.archivewatch.android

import app.archivewatch.android.ui.uniqueBy
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The crash this guards against is not thrown here — Compose throws it, deep
 * inside `subcompose`, with no frame of ours in the stack, which is exactly why
 * it read as a Compose fault for weeks rather than a data one.
 *
 * So the test asserts the PROPERTY Compose requires instead: after `uniqueBy`
 * the key list has no repeats, and the FIRST occurrence survives, because the
 * order a shelf arrives in is a ranking somebody already decided.
 */
class UniqueByTest {
    private data class Item(val id: String, val n: Int)

    @Test
    fun `drops a repeated key and keeps the first`() {
        val out = listOf(Item("a", 1), Item("b", 2), Item("a", 3)).uniqueBy { it.id }
        assertEquals(listOf(1, 2), out.map { it.n })
    }

    @Test
    fun `a list with no repeats is returned unchanged`() {
        val src = listOf(Item("a", 1), Item("b", 2), Item("c", 3))
        assertEquals(src, src.uniqueBy { it.id })
    }

    @Test
    fun `keys are unique afterwards, which is all Compose asks`() {
        val src = (1..50).map { Item(listOf("a", "b", "c")[it % 3], it) }
        val keys = src.uniqueBy { it.id }.map { it.id }
        assertEquals(keys.size, keys.toSet().size)
    }

    @Test
    fun `a null key repeats like any other value`() {
        val out = listOf(Item("a", 1), Item("b", 2), Item("c", 3))
            .uniqueBy { it.id.takeIf { k -> k == "a" } }
        assertEquals(listOf(1, 2), out.map { it.n })
    }

    @Test
    fun `empty and single-element lists are returned as they are`() {
        assertEquals(emptyList<Item>(), emptyList<Item>().uniqueBy { it.id })
        val one = listOf(Item("a", 1))
        assertEquals(one, one.uniqueBy { it.id })
    }
}
