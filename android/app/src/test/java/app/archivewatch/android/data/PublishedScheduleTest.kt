package app.archivewatch.android.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Channels on one clock (ANDROID-DESIGN §4.6): Android only EXPANDS
 *  channel-schedule.json, with tools/build_channel_schedule.py's arithmetic. */
class PublishedScheduleTest {
    // 1790467200 = 2026-09-27 00:00 UTC. The 27th's last program runs past
    // midnight; the 28th starts where it ended (its own `start`).
    private val text = """
        {"schema":1,"gap":120,
         "programs":{"a":["Film A",5400,"https://x/a.mp4","feature-film"],
                     "gone":["Old Film",null,"https://x/g.mp4","silent-film"]},
         "channels":[{"id":"drama","title":"Drama","tagline":"","accent":"#FF5C35",
           "days":{"2026-09-28":{"start":1790554560,"slots":[["a",5400]]},
                   "2026-09-27":{"start":1790467200,"slots":[["a",5400],["gone",81000],["missing",600]]}}}]}
    """.trimIndent()

    @Test fun `slots follow one another with the gap, across UTC days in date order`() {
        val slots = PublishedSchedule.parse(text)!!.channels.single().slots
        assertEquals(listOf("a", "gone", "missing", "a"), slots.map { it.id })
        assertEquals(1790467200_000L, slots[0].startMs)
        assertEquals(1790467200_000L + 5400_000L, slots[0].endMs)
        assertEquals(slots[0].endMs + 120_000L, slots[1].startMs)
        assertEquals(slots[1].endMs + 120_000L, slots[2].startMs)
        // Continuity across UTC midnight: day two begins at day one's end + gap.
        assertEquals(slots[2].endMs + 120_000L, slots[3].startMs)
    }

    @Test fun `an id the device lacks plays from the file's own facts, and none is dropped`() {
        val s = PublishedSchedule.parse(text)!!
        val dbA = CatalogItem(archiveID = "a", title = "Film A (device)", downloadURL = "https://db/a.mp4")
        val g = s.guide(Long.MIN_VALUE, Long.MAX_VALUE, mapOf("a" to dbA)).single()
        assertEquals(4, g.slots.size)
        assertEquals("Film A (device)", g.slots[0].item.title)
        assertEquals("Old Film", g.slots[1].item.title)
        assertEquals("https://x/g.mp4", g.slots[1].item.downloadURL)
        assertEquals("silent-film", g.slots[1].item.contentType)
        // Neither the DB nor the file knows it: still on the guide, at its time.
        assertEquals("missing", g.slots[2].item.title)
        assertEquals(s.channels.single().slots.map { it.startMs }, g.slots.map { it.startMs })
    }

    @Test fun `the window keeps a program that started before it`() {
        val s = PublishedSchedule.parse(text)!!
        val from = 1790467200_000L + 3600_000L
        val g = s.guide(from, from + 60_000L, emptyMap()).single()
        assertEquals(listOf("a"), g.slots.map { it.item.archiveID })
    }

    @Test fun `a schema this build does not know is refused, not guessed`() {
        assertNull(PublishedSchedule.parse(text.replace("\"schema\":1", "\"schema\":2")))
        assertNull(PublishedSchedule.parse("not json"))
    }
}
