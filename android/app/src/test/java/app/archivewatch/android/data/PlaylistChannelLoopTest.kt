package app.archivewatch.android.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** A playlist channel (Apple's `ChannelScheduler.loop`): the playlist IN
 *  ORDER, on one clock from 2026-01-01T00:00:00Z. */
class PlaylistChannelLoopTest {
    private fun film(id: String, sec: Int) =
        CatalogItem(archiveID = id, title = id, runtimeSeconds = sec, downloadURL = "https://x/$id.mp4")
    private val list = listOf(film("a", 3600), film("b", 1800), film("c", 600))
    // Each program's place on the clock: its start, mod the cycle, is fixed.
    private val cycleMs = (3600 + 120 + 1800 + 120 + 600 + 120) * 1000L
    private val offsetMs = mapOf("a" to 0L, "b" to 3720_000L, "c" to 5640_000L)
    private val now = 1_795_000_000_000L   // 2026-11-18, mid-cycle

    @Test fun `slots play the playlist in its order, looping`() {
        val ids = ChannelScheduler.loop(list, now).map { it.item.archiveID }
        assertTrue(ids.size > 6)
        val start = list.indexOfFirst { it.archiveID == ids[0] }
        ids.forEachIndexed { k, id -> assertEquals(list[(start + k) % list.size].archiveID, id) }
    }

    @Test fun `every slot sits on the one clock, on any day`() {
        for (day in 0..3) {
            val slots = ChannelScheduler.loop(list, now + day * 86_400_000L)
            for (s in slots) {
                assertEquals(offsetMs.getValue(s.item.archiveID),
                             (s.startMs - ChannelScheduler.LOOP_EPOCH_MS).mod(cycleMs))
            }
            val anchor = ChannelScheduler.dayAnchorMs(now + day * 86_400_000L)
            assertTrue(slots[0].startMs <= anchor && anchor < slots[0].endMs + 120_000L)
            for (k in 1 until slots.size) assertEquals(slots[k - 1].endMs + 120_000L, slots[k].startMs)
        }
    }

    @Test fun `a playlist channel keeps the viewer's titles, repeats included, minus what cannot play`() {
        val series = CatalogItem(archiveID = "s", contentType = "tv-series", downloadURL = "https://x/s.mp4")
        val noFile = CatalogItem(archiveID = "n")
        val picked = ChannelScheduler.playlistPrograms(listOf(list[2], series, list[0], noFile, list[2]))
        assertEquals(listOf("c", "a", "c"), picked.map { it.archiveID })
    }
}
