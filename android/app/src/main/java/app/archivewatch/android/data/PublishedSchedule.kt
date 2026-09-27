package app.archivewatch.android.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

// Channels on ONE clock (ORPHANED-FILMS #2, ANDROID-DESIGN §4.6). The pipeline
// publishes channel-schedule.json (tools/build_channel_schedule.py): one UTC
// timeline per preset channel, the same for every viewer on every platform.
// This file only EXPANDS it; nothing here orders, shuffles or anchors.

/** A program's own facts, carried by the file for ids the device DB lacks. */
data class PublishedProgram(
    val title: String,
    val runtimeSeconds: Int?,
    val url: String?,
    val contentType: String,
)

data class PublishedSlot(val id: String, val startMs: Long, val endMs: Long)

data class PublishedChannel(
    val id: String,
    val title: String,
    val accentHex: String,
    val slots: List<PublishedSlot>,
)

data class PublishedSchedule(
    val programs: Map<String, PublishedProgram>,
    val channels: List<PublishedChannel>,
) {
    val firstStartMs: Long? get() = channels.mapNotNull { it.slots.firstOrNull()?.startMs }.minOrNull()
    val lastEndMs: Long? get() = channels.mapNotNull { it.slots.lastOrNull()?.endMs }.maxOrNull()

    companion object {
        /** Null when the text is not a schedule this build understands. */
        fun parse(text: String, json: Json = Json): PublishedSchedule? = runCatching {
            val root = json.parseToJsonElement(text).jsonObject
            if (root["schema"]?.jsonPrimitive?.intOrNull != 1) return null
            val gap = root["gap"]?.jsonPrimitive?.longOrNull ?: 120L
            val programs = root["programs"]?.jsonObject.orEmpty().mapValues { (_, v) ->
                val a = v.jsonArray
                PublishedProgram(
                    title = a.getOrNull(0)?.jsonPrimitive?.contentOrNull.orEmpty(),
                    runtimeSeconds = a.getOrNull(1)?.takeIf { it !is JsonNull }?.jsonPrimitive?.intOrNull,
                    url = a.getOrNull(2)?.takeIf { it !is JsonNull }?.jsonPrimitive?.contentOrNull,
                    contentType = a.getOrNull(3)?.takeIf { it !is JsonNull }?.jsonPrimitive?.contentOrNull
                        ?: "feature-film",
                )
            }
            val channels = root["channels"]?.jsonArray.orEmpty().map { c ->
                val o = c.jsonObject
                PublishedChannel(
                    id = o["id"]!!.jsonPrimitive.content,
                    title = o["title"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                    accentHex = o["accent"]?.jsonPrimitive?.contentOrNull ?: "#0047FF",
                    slots = expand(o["days"]?.jsonObject ?: JsonObject(emptyMap()), gap),
                )
            }
            PublishedSchedule(programs, channels)
        }.getOrNull()

        /**
         * A day's slot i starts at day.start + the durations and gaps before
         * it; days are UTC dates and follow one another, so sorting the keys
         * gives the channel's single timeline.
         */
        fun expand(days: JsonObject, gapSec: Long): List<PublishedSlot> {
            val out = ArrayList<PublishedSlot>()
            for (key in days.keys.sorted()) {
                val day = days[key]!!.jsonObject
                var t = day["start"]!!.jsonPrimitive.longOrNull!! * 1000
                for (s in (day["slots"] as? JsonArray).orEmpty()) {
                    val pair = s.jsonArray
                    val secs = pair[1].jsonPrimitive.longOrNull ?: continue
                    val end = t + secs * 1000
                    out.add(PublishedSlot(pair[0].jsonPrimitive.content, t, end))
                    t = end + gapSec * 1000
                }
            }
            return out
        }
    }
}

/**
 * The guide rows for the preset channels: each slot keeps its published time,
 * played by the device's own catalog card when it has one and by the file's
 * facts when it does not — a slot is never dropped, a time never moved.
 */
fun PublishedSchedule.guide(
    fromMs: Long,
    untilMs: Long,
    db: Map<String, CatalogItem>,
): List<GuideChannel> = channels.mapNotNull { ch ->
    val slots = ch.slots.filter { it.endMs > fromMs && it.startMs < untilMs }.map { s ->
        val item = db[s.id] ?: programs[s.id].let { p ->
            CatalogItem(
                archiveID = s.id,
                title = p?.title ?: s.id,
                contentType = p?.contentType ?: "feature-film",
                runtimeSeconds = p?.runtimeSeconds,
                downloadURL = p?.url,
            )
        }
        ScheduledProgram(item, s.startMs, s.endMs)
    }
    if (slots.isEmpty()) null else GuideChannel(ch.id, ch.title, ch.accentHex, slots)
}
