package app.archivewatch.android.data

/**
 * Channel up/down without leaving the picture (iOS-DESIGN §2.5d, tvOS and
 * macOS alike): the guide a channel was tuned from, so the player can step to
 * the channel above or below it. The rule is Apple's `GuideChannel.surf`.
 */
object ChannelSurf {
    /** The guide the current channel came from; the player never outlives it. */
    var channels: List<GuideChannel> = emptyList()
        private set

    /** Step `step` rows from `from`, wrapping, skipping a channel with nothing
     *  on now or later. Joins the program airing now at its current second, or
     *  the next one if it is between two. */
    fun hop(from: Int, step: Int, nowMs: Long = System.currentTimeMillis()): Pair<Int, ScheduledProgram>? {
        val n = channels.size
        if (n == 0) return null
        for (k in 1..n) {
            val i = ((from + step * k) % n + n) % n
            val slots = channels[i].slots
            val slot = slots.firstOrNull { it.contains(nowMs) }
                ?: slots.firstOrNull { it.startMs > nowMs }
                ?: continue
            return i to slot
        }
        return null
    }

    /** The player's spec for `slot` on channel `index`: the lineup from that
     *  program on, with a vintage commercial between programs (#89). */
    fun spec(guide: List<GuideChannel>, index: Int, slot: ScheduledProgram, ads: List<CatalogItem>,
             nowMs: Long = System.currentTimeMillis()): PlaySpec? {
        channels = guide
        val channel = guide[index]
        val lineup = ChannelScheduler.lineup(channel.slots, maxOf(slot.startMs, nowMs))
            .let { if (it.firstOrNull()?.item?.archiveID != slot.item.archiveID) listOf(slot) + it else it }
        val entries = ArrayList<QueueEntry>()
        lineup.forEachIndexed { i, sched ->
            sched.item.downloadURL?.let { entries.add(QueueEntry(sched.item.archiveID, sched.item.title, channel.title, it)) }
            if (ads.isNotEmpty() && i < lineup.size - 1) {
                val ad = ads[i % ads.size]
                ad.downloadURL?.let { entries.add(QueueEntry(ad.archiveID, ad.title, "Commercial break", it)) }
            }
        }
        if (entries.isEmpty()) return null
        return PlaySpec(
            id = entries.first().id,
            title = entries.first().title,
            subtitle = channel.title,
            url = entries.first().url,
            queue = entries,
            queueIndex = 0,
            startPositionMs = if (slot.contains(nowMs)) maxOf(0L, nowMs - slot.startMs) else 0L,
            persistProgress = false,   // channels never persist resume
            channelIndex = index,
        )
    }

    /** The spec for the channel `step` rows away, or null if none has anything on. */
    fun step(from: Int, step: Int, ads: List<CatalogItem>): PlaySpec? {
        val (i, slot) = hop(from, step) ?: return null
        return spec(channels, i, slot, ads)
    }
}
