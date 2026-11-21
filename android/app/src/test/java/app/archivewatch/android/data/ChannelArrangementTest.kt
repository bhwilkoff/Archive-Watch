package app.archivewatch.android.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Arrange channels: one rule with Apple's `GuideChannel.arranged`. */
class ChannelArrangementTest {
    private fun ch(id: String) = GuideChannel(id, id, "#000000", emptyList())
    private val guide = listOf("user-uc-1", "drama", "comedy", "noir", "western").map(::ch)

    @Test fun `named channels lead in the order's order, the rest follow where they stood`() {
        val out = ChannelArrangement.arranged(guide, listOf("western", "user-uc-1"))
        assertEquals(listOf("western", "user-uc-1", "drama", "comedy", "noir"), out.map { it.id })
    }

    @Test fun `no order keeps the default, and unknown or repeated ids change nothing`() {
        assertEquals(guide, ChannelArrangement.arranged(guide, emptyList()))
        val out = ChannelArrangement.arranged(guide, listOf("gone", "noir", "noir", "user-deleted"))
        assertEquals(listOf("noir", "user-uc-1", "drama", "comedy", "western"), out.map { it.id })
    }

    @Test fun `moves to the top, up and down, and refuses a move past either end`() {
        val ids = guide.map { it.id }
        assertEquals(listOf("noir", "user-uc-1", "drama", "comedy", "western"),
                     ChannelArrangement.moved(ids, "noir", ChannelArrangement.TO_TOP))
        assertEquals(listOf("user-uc-1", "comedy", "drama", "noir", "western"),
                     ChannelArrangement.moved(ids, "comedy", -1))
        assertEquals(listOf("user-uc-1", "drama", "noir", "comedy", "western"),
                     ChannelArrangement.moved(ids, "comedy", 1))
        assertNull(ChannelArrangement.moved(ids, "user-uc-1", -1))
        assertNull(ChannelArrangement.moved(ids, "western", 1))
        assertNull(ChannelArrangement.moved(ids, "missing", 1))
    }
}
