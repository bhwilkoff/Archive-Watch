package app.archivewatch.android.data

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** My Order (Apple `Playlist.inMyOrder` / `arrange`) and the Drive blob's
 *  playlist entry, which must carry `sortIndex` both ways. */
class PlaylistOrderTest {

    private fun pl(id: String, created: Long, index: Int? = null, mod: Long = created) =
        UserPlaylist(id, id, listOf("a", "b"), created, mod, index)

    @Test
    fun `unplaced lists lead, newest first, then placed lists by their place`() {
        val lists = listOf(
            pl("placed2", 1, 2), pl("oldNew", 10), pl("placed0", 5, 0),
            pl("newNew", 20), pl("placed1", 30, 1),
        )
        assertEquals(listOf("newNew", "oldNew", "placed0", "placed1", "placed2"),
                     PlaylistOrder.inMyOrder(lists).map { it.id })
    }

    @Test
    fun `a shared place is broken newest first`() {
        val lists = listOf(pl("old", 1, 0), pl("new", 2, 0))
        assertEquals(listOf("new", "old"), PlaylistOrder.inMyOrder(lists).map { it.id })
    }

    @Test
    fun `arrange stamps only the lists whose place changed`() {
        val ordered = listOf(pl("a", 1, 0), pl("c", 3, 2), pl("b", 2, 1))
        val changed = PlaylistOrder.arrange(ordered, now = 99)
        assertEquals(listOf("c" to 1, "b" to 2), changed.map { it.id to it.sortIndex })
        assertTrue(changed.all { it.modifiedAt == 99L })
        // Control: an order that already matches its places changes nothing.
        assertTrue(PlaylistOrder.arrange(listOf(pl("a", 1, 0), pl("b", 2, 1)), 99).isEmpty())
    }

    @Test
    fun `arranging an unplaced list gives every list a place`() {
        val mine = PlaylistOrder.inMyOrder(listOf(pl("x", 1, 0), pl("new", 5)))
        val moved = PlaylistOrder.moved(mine, 0, 1)
        assertEquals(listOf("x", "new"), moved.map { it.id })
        val changed = PlaylistOrder.arrange(moved, 7).associateBy { it.id }
        assertEquals(setOf("new"), changed.keys)      // x already holds place 0
        assertEquals(1, changed["new"]?.sortIndex)
        val after = moved.map { changed[it.id] ?: it }
        assertEquals(listOf("x", "new"), PlaylistOrder.inMyOrder(after).map { it.id })
    }

    @Test
    fun `moved moves one entry and ignores an index out of range`() {
        assertEquals(listOf(2, 1, 3), PlaylistOrder.moved(listOf(1, 2, 3), 1, 0))
        assertEquals(listOf(1, 3, 2), PlaylistOrder.moved(listOf(1, 2, 3), 1, 2))
        assertEquals(listOf(1, 2, 3), PlaylistOrder.moved(listOf(1, 2, 3), 2, 3))
    }

    @Test
    fun `list sorts - names ignore case, dates are when the list was made`() {
        val lists = listOf(pl("beta", 2), pl("Alpha", 3), pl("gamma", 1))
        assertEquals(listOf("Alpha", "beta", "gamma"),
                     PlaylistOrder.sortedLists(lists, PlaylistSort.ALPHABETICAL).map { it.id })
        assertEquals(listOf("gamma", "beta", "Alpha"),
                     PlaylistOrder.sortedLists(lists, PlaylistSort.REVERSE_ALPHABETICAL).map { it.id })
        assertEquals(listOf("Alpha", "beta", "gamma"),
                     PlaylistOrder.sortedLists(lists, PlaylistSort.NEWEST).map { it.id })
        assertEquals(listOf("gamma", "beta", "Alpha"),
                     PlaylistOrder.sortedLists(lists, PlaylistSort.OLDEST).map { it.id })
    }

    @Test
    fun `film sorts put a film with no year last either way`() {
        val films = listOf(
            CatalogItem("n", title = "nosferatu", year = 1922),
            CatalogItem("u", title = "Undated"),
            CatalogItem("m", title = "Metropolis", year = 1927),
        )
        fun ids(s: PlaylistSort) = PlaylistOrder.sortedFilms(films, s) { it }.map { it.archiveID }
        assertEquals(listOf("n", "u", "m"), ids(PlaylistSort.MY_ORDER))
        assertEquals(listOf("m", "n", "u"), ids(PlaylistSort.ALPHABETICAL))
        assertEquals(listOf("u", "n", "m"), ids(PlaylistSort.REVERSE_ALPHABETICAL))
        assertEquals(listOf("m", "n", "u"), ids(PlaylistSort.NEWEST))
        assertEquals(listOf("n", "m", "u"), ids(PlaylistSort.OLDEST))
    }

    @Test
    fun `the persisted keys are the Apple raw values`() {
        assertEquals(listOf("myOrder", "alphabetical", "reverseAlphabetical", "newest", "oldest"),
                     PlaylistSort.entries.map { it.key })
        PlaylistSort.entries.forEach { assertEquals(it, PlaylistSort.fromKey(it.key)) }
        assertNull(PlaylistSort.fromKey("bogus"))
        assertEquals("playlistSort.lists", PlaylistOrder.LIST_KEY)
        assertEquals("playlistSort.pl-1", PlaylistOrder.contentsKey("pl-1"))
    }

    // --- Drive round trip ---

    private fun roundTrip(p: UserPlaylist, mine: UserPlaylist? = null): UserPlaylist? =
        PlaylistOrder.fromJson(JSONObject(PlaylistOrder.toJson(p).toString()), mine)

    @Test
    fun `a place survives the Drive blob`() {
        val p = UserPlaylist("pl-1", "Noir", listOf("a", "b"), 100, 200, 3)
        assertEquals(p, roundTrip(p))
    }

    @Test
    fun `an unplaced list is written as null and read back as null`() {
        val p = UserPlaylist("pl-1", "Noir", listOf("a"), 100, 200, null)
        assertTrue(PlaylistOrder.toJson(p).has("sortIndex"))
        assertNull(roundTrip(p, mine = p.copy(sortIndex = 4))?.sortIndex)
    }

    @Test
    fun `a writer that drops the field does not erase this device's place`() {
        val cloud = JSONObject().put("id", "pl-1").put("name", "Noir")
            .put("archiveIDs", org.json.JSONArray(listOf("a"))).put("createdAt", 100).put("modifiedAt", 300)
        val mine = UserPlaylist("pl-1", "Noir", listOf("a"), 100, 200, 5)
        assertEquals(5, PlaylistOrder.fromJson(cloud, mine)?.sortIndex)
        // Control: with nothing local there is no place to keep.
        assertNull(PlaylistOrder.fromJson(cloud, null)?.sortIndex)
    }

    @Test
    fun `a list keeps its own createdAt from the cloud`() {
        val p = UserPlaylist("pl-1", "Noir", listOf("a"), 100, 900, 0)
        assertEquals(100L, roundTrip(p)?.createdAt)
        val noCreated = JSONObject().put("id", "pl-2").put("modifiedAt", 900)
        assertEquals(900L, PlaylistOrder.fromJson(noCreated, null)?.createdAt)
        assertNull(PlaylistOrder.fromJson(JSONObject().put("name", "no id"), null))
    }
}
