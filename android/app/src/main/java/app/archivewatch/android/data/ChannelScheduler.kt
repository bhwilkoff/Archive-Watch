package app.archivewatch.android.data

import java.util.Calendar

// Kotlin port of the shared date-seeded channel scheduler
// (ArchiveWatch Services/ChannelScheduler.swift + Models/Channels.swift).
// Same presets, same 6 AM broadcast-day anchor, same FNV-1a(channelID+day)
// seed into SplitMix64, same per-type runtime defaults and 2-minute
// inter-program buffer — so an Android device shows the same channel
// PERSONALITY on the same day as the Apple apps (cross-ecosystem schedule
// identity is approximate, not byte-exact: shuffle bound mapping differs
// from Swift's RandomNumberGenerator and the device DB build may differ).

/** Channel presets — same ids/pools as the Apple apps. */
data class ChannelPreset(
    val id: String,
    val title: String,
    val tagline: String,
    val accentHex: String,
    val contentType: String? = null,
    val genre: String? = null,
)

object ChannelPresets {
    val all = listOf(
        ChannelPreset("drama", "Drama Theater", "The big stories", "#FF5C35", genre = "Drama"),
        ChannelPreset("comedy", "Comedy Hour", "Laughs around the clock", "#E8A317", genre = "Comedy"),
        ChannelPreset("noir", "Crime & Mystery", "Shadows and suspects", "#2D5BFF", genre = "Crime"),
        ChannelPreset("thrill", "Thriller", "Edge of your seat", "#0047FF", genre = "Thriller"),
        ChannelPreset("horror", "Horror", "After dark", "#7C5BBA", genre = "Horror"),
        ChannelPreset("western", "Western Trail", "The frontier rolls on", "#C9A66B", genre = "Western"),
        ChannelPreset("scifi", "Sci-Fi Theater", "Worlds beyond", "#3FA796", genre = "Science Fiction"),
        ChannelPreset("silent", "Silent Cinema", "The age before sound", "#C9A66B", contentType = "silent-film"),
        ChannelPreset("cartoon", "Cartoon Classics", "Animation all day", "#FF4D8D", contentType = "animation"),
        ChannelPreset("news", "Newsreel Desk", "History as it broke", "#8A8F98", contentType = "newsreel"),
        ChannelPreset("docs", "Documentary", "Real stories", "#3FA796", contentType = "documentary"),
        ChannelPreset("tv", "Classic TV", "Vintage television", "#2D5BFF", contentType = "tv-special"),
        ChannelPreset("tv-comedy", "TV Comedy", "Sitcoms & sketch", "#E8A317", contentType = "tv-special", genre = "Comedy"),
        ChannelPreset("tv-drama", "TV Drama", "Series drama", "#FF5C35", contentType = "tv-special", genre = "Drama"),
        ChannelPreset("tv-western", "TV Westerns", "Saddle up, every hour", "#C9A66B", contentType = "tv-special", genre = "Western"),
    )
}

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
