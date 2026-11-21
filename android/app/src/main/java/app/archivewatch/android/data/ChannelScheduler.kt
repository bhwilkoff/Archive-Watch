package app.archivewatch.android.data

import java.util.Calendar

// PRESET channels no longer use this: they play the pipeline's one UTC
// timeline (PublishedSchedule.kt, channel-schedule.json). What remains
// schedules a viewer's OWN channels, which are theirs alone.
//
// Kotlin port of the shared date-seeded channel scheduler
// (ArchiveWatch Services/ChannelScheduler.swift): a 6 AM local broadcast
// day, FNV-1a(channelID+day) into SplitMix64, per-type runtime defaults and
// a 2-minute buffer.

data class ScheduledProgram(
    val item: CatalogItem,
    val startMs: Long,
    val endMs: Long,
) {
    fun contains(t: Long): Boolean = t in startMs until endMs
}

data class GuideChannel(
    val id: String,
    val title: String,
    val accentHex: String,
    val slots: List<ScheduledProgram>,
)

object ChannelScheduler {

    /** The broadcast day starts at 6:00 AM local and runs 24h. */
    fun dayAnchorMs(nowMs: Long): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = nowMs
            set(Calendar.HOUR_OF_DAY, 6)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        var anchor = cal.timeInMillis
        if (nowMs < anchor) anchor -= 24 * 3600_000L
        return anchor
    }

    /** Default runtime when an item has none, by content type (seconds). */
    private fun runtimeSec(item: CatalogItem): Long {
        val s = item.runtimeSeconds
        if (s != null && s > 120) return minOf(s.toLong(), 3 * 3600L)
        return when (item.contentType) {
            "feature-film", "silent-film" -> 90 * 60L
            "tv-special", "documentary" -> 50 * 60L
            "short-film", "animation", "newsreel", "ephemeral" -> 12 * 60L
            else -> 3600L
        }
    }

    /** Deterministic day timeline: pool shuffled by hash(channelID+day), packed
     *  from the 6 AM anchor until `coverHours` past now. */
    fun schedule(
        channelID: String,
        programs: List<CatalogItem>,
        nowMs: Long,
        coverHours: Double = 26.0,
        bufferSec: Long = 120,
    ): List<ScheduledProgram> {
        if (programs.isEmpty()) return emptyList()
        val anchor = dayAnchorMs(nowMs)
        val cal = Calendar.getInstance().apply { timeInMillis = anchor }
        val dayKey = "${cal.get(Calendar.YEAR)}-${cal.get(Calendar.MONTH) + 1}-${cal.get(Calendar.DAY_OF_MONTH)}"
        val rng = SplitMix(fnv1a(channelID + dayKey))
        val ordered = programs.toMutableList()
        shuffle(ordered, rng)

        val out = ArrayList<ScheduledProgram>()
        var cursor = anchor
        val coverUntil = nowMs + (coverHours * 3600_000.0).toLong()
        var i = 0
        while (cursor < coverUntil && out.size < 2000) {
            val item = ordered[i % ordered.size]
            val end = cursor + runtimeSec(item) * 1000
            out.add(ScheduledProgram(item, cursor, end))
            cursor = end + bufferSec * 1000
            i += 1
        }
        return out
    }

    /** One clock for every playlist channel: 2026-01-01T00:00:00Z. */
    const val LOOP_EPOCH_MS = 1_767_225_600_000L

    /** A playlist channel's titles: the viewer's own choices in their order,
     *  so no recommendation gate, only what has a file to play. */
    fun playlistPrograms(items: List<CatalogItem>): List<CatalogItem> =
        items.filter { it.contentType != "tv-series" && !it.downloadURL.isNullOrBlank() }

    /** A playlist channel (Apple's `ChannelScheduler.loop`): the programs IN
     *  ORDER, looping on one clock from [LOOP_EPOCH_MS], so every device airs
     *  the same title at the same moment and a day picks up where the last
     *  left off. Packed from the broadcast day anchor. */
    fun loop(
        programs: List<CatalogItem>,
        nowMs: Long,
        coverHours: Double = 26.0,
        bufferSec: Long = 120,
    ): List<ScheduledProgram> {
        if (programs.isEmpty()) return emptyList()
        val anchor = dayAnchorMs(nowMs)
        val lengths = programs.map { (runtimeSec(it) + bufferSec) * 1000 }
        val cycle = lengths.sum()
        var into = (anchor - LOOP_EPOCH_MS).mod(cycle)
        var i = 0
        while (into >= lengths[i]) { into -= lengths[i]; i = (i + 1) % programs.size }
        var cursor = anchor - into
        val coverUntil = nowMs + (coverHours * 3600_000.0).toLong()
        val out = ArrayList<ScheduledProgram>()
        while (cursor < coverUntil && out.size < 2000) {
            val item = programs[i]
            val end = cursor + runtimeSec(item) * 1000
            out.add(ScheduledProgram(item, cursor, end))
            cursor = end + bufferSec * 1000
            i = (i + 1) % programs.size
        }
        return out
    }

    /** The lineup to hand the player when tuning in at `t`: the slot containing
     *  (or next after) `t`, then everything scheduled after it. */
    fun lineup(slots: List<ScheduledProgram>, atMs: Long): List<ScheduledProgram> {
        val idx = slots.indexOfFirst { it.contains(atMs) }
            .takeIf { it >= 0 }
            ?: slots.indexOfFirst { it.startMs >= atMs }.takeIf { it >= 0 }
            ?: 0
        return slots.drop(idx)
    }

    // --- deterministic seed plumbing (matches the Swift constants) ---

    private fun fnv1a(s: String): ULong {
        var h = 1469598103934665603uL
        for (b in s.encodeToByteArray()) {
            h = (h xor b.toUByte().toULong()) * 1099511628211uL
        }
        return h
    }

    class SplitMix(seed: ULong) {
        private var state = seed + 0x9E3779B97F4A7C15uL
        fun next(): ULong {
            state += 0x9E3779B97F4A7C15uL
            var z = state
            z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
            z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
            return z xor (z shr 31)
        }
    }

    private fun shuffle(list: MutableList<CatalogItem>, rng: SplitMix) {
        for (i in list.size - 1 downTo 1) {
            val j = (rng.next() % (i + 1).toULong()).toInt()
            val t = list[i]; list[i] = list[j]; list[j] = t
        }
    }
}
