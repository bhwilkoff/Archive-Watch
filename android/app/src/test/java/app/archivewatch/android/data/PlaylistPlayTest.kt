package app.archivewatch.android.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/** iOS-DESIGN §4.3b: a playlist plays. */
class PlaylistPlayTest {

    private fun film(id: String, url: String? = "https://archive.org/download/$id/$id.mp4") =
        CatalogItem(id, title = id, downloadURL = url)

    private fun shown(vararg ids: String) = ids.map { it to film(it) }

    @Test
    fun `play starts at the first title not marked watched`() {
        val spec = PlaylistPlay.play(shown("a", "b", "c"), watched = setOf("a"))!!
        assertEquals(1, spec.queueIndex)
        assertEquals("b", spec.id)
        assertEquals(listOf("a", "b", "c"), spec.queue.map { it.id })
    }

    @Test
    fun `a watched title later in the list does not move the start`() {
        assertEquals(0, PlaylistPlay.play(shown("a", "b", "c"), setOf("b"))!!.queueIndex)
    }

    @Test
    fun `all watched starts at the top`() {
        val spec = PlaylistPlay.play(shown("a", "b"), setOf("a", "b"))!!
        assertEquals(0, spec.queueIndex)
        assertEquals("a", spec.id)
    }

    @Test
    fun `play follows the order given, not the id order`() {
        val spec = PlaylistPlay.play(shown("z", "m", "a"), emptySet())!!
        assertEquals(listOf("z", "m", "a"), spec.queue.map { it.id })
    }

    @Test
    fun `history under a merged-away id counts as watched`() {
        val shown = listOf("old" to film("survivor"), "b" to film("b"))
        assertEquals("b", PlaylistPlay.play(shown, setOf("old"))!!.id)
    }

    @Test
    fun `a title with no file and a series card are skipped`() {
        val shown = listOf(
            "s" to CatalogItem("s", contentType = "tv-series", downloadURL = "https://x/s.mp4"),
            "n" to film("n", url = null),
            "a" to film("a"),
            "b" to film("b"),
        )
        val spec = PlaylistPlay.play(shown, emptySet())!!
        assertEquals(listOf("a", "b"), spec.queue.map { it.id })
        assertEquals("a", spec.id)
    }

    @Test
    fun `nothing playable plays nothing`() {
        val shown = listOf("n" to film("n", url = null))
        assertNull(PlaylistPlay.play(shown, emptySet()))
        assertNull(PlaylistPlay.shuffle(shown))
    }

    @Test
    fun `shuffle plays each title once, from the first`() {
        val ids = (1..50).map { "t$it" }
        val spec = PlaylistPlay.shuffle(shown(*ids.toTypedArray()), Random(7))!!
        assertEquals(ids.size, spec.queue.size)
        assertEquals(ids.toSet(), spec.queue.map { it.id }.toSet())
        assertEquals(0, spec.queueIndex)
        assertEquals(spec.queue.first().id, spec.id)
        assertNotEquals(ids, spec.queue.map { it.id })
    }

    @Test
    fun `each shuffle is a fresh order`() {
        val list = shown(*(1..50).map { "t$it" }.toTypedArray())
        val r = Random(11)
        val one = PlaylistPlay.shuffle(list, r)!!.queue.map { it.id }
        val two = PlaylistPlay.shuffle(list, r)!!.queue.map { it.id }
        assertNotEquals(one, two)
    }

    @Test
    fun `one title is a queue of one, so Autoplay cannot follow it`() {
        val spec = PlaylistPlay.play(shown("a"), emptySet())!!
        assertEquals(1, spec.queue.size)
        assertTrue(spec.playlist)
        assertTrue(spec.persistProgress)
    }

    @Test
    fun `each title keeps its own tracks`() {
        val cap = Caption(lang = "en", url = "https://x/b.vtt")
        val shown = listOf("a" to film("a"), "b" to film("b").copy(captions = listOf(cap)))
        val spec = PlaylistPlay.play(shown, emptySet())!!
        assertEquals(emptyList<Caption>(), spec.captionsFor("a"))
        assertEquals(listOf(cap), spec.captionsFor("b"))
    }

    @Test
    fun `an episode queue keeps the pressed episode's tracks and shows none for the next`() {
        val cap = Caption(lang = "en", url = "https://x/e1.vtt")
        val spec = PlaySpec(
            id = "e1", title = "", url = "u", captions = listOf(cap),
            queue = listOf(QueueEntry("e1", "", url = "u"), QueueEntry("e2", "", url = "v")),
        )
        assertEquals(listOf(cap), spec.captionsFor("e1"))
        assertEquals(emptyList<Caption>(), spec.captionsFor("e2"))
    }

    @Test
    fun `the position counts from one and a single title has none`() {
        assertEquals("3 of 12", PlaylistPlay.position(2, 12))
        assertNull(PlaylistPlay.position(0, 1))
        assertNull(PlaylistPlay.position(-1, 12))
    }
}
