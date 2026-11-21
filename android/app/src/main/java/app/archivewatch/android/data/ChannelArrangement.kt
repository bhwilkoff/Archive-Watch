package app.archivewatch.android.data

/**
 * The viewer's channel order (Apple's `GuideChannel.arranged` and the tvOS
 * long-press moves): one rule on every platform, so a synced order lands on
 * the same guide everywhere.
 */
object ChannelArrangement {

    /** The ids `order` names first, in its order; every other channel after,
     *  where it already stood. */
    fun arranged(channels: List<GuideChannel>, order: List<String>): List<GuideChannel> {
        if (order.isEmpty()) return channels
        val rank = HashMap<String, Int>()
        order.forEachIndexed { i, id -> rank.putIfAbsent(id, i) }
        val named = channels.filter { it.id in rank }.sortedBy { rank.getValue(it.id) }
        return named + channels.filter { it.id !in rank }
    }

    const val TO_TOP = Int.MIN_VALUE

    /** `ids` with `id` moved `step` places (-1 up, +1 down) or to the top
     *  ([TO_TOP]); null when nothing would change. */
    fun moved(ids: List<String>, id: String, step: Int): List<String>? {
        val from = ids.indexOf(id)
        if (from < 0) return null
        val to = if (step == TO_TOP) 0 else (from + step).coerceIn(0, ids.size - 1)
        if (to == from) return null
        return ids.toMutableList().apply { add(to, removeAt(from)) }
    }
}
