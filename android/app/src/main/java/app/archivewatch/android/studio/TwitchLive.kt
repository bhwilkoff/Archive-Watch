package app.archivewatch.android.studio

// Twitch's live API, on Android (docs/WATCH-TOGETHER.md §4, §6.1).
//
// The Kotlin counterpart of the Swift `TwitchLive`. It exists so Android can
// resolve a REAL destination: until now `StudioController` could only publish
// to a bench address, which is the same defect §9.ccc found on tvOS and macOS —
// an engine that composites, encodes and reports healthy while reaching nobody.
//
// §5 BINDS HERE HARDEST. A stream key is a credential: never logged, never
// written to disk, never put in a URL this app prints, and it does not outlive
// the session that fetched it. So the key is returned to exactly one caller,
// joined to the server at the moment of publishing, and this file has no
// logging in it at all — not even on the error paths, where a key-bearing URL
// would be the natural thing to include.

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/** Where the program goes, and the key that opens it. Never logged. */
data class StreamCredentials(
    val server: String,
    val key: String,
    val backupServer: String?,
    val broadcasterId: String,
)

class TwitchLive(private val token: String, private val clientId: String) {

    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private fun helix(path: String, query: Map<String, String> = emptyMap()): Request.Builder {
        val url = StringBuilder("https://api.twitch.tv/helix").append(path)
        if (query.isNotEmpty()) {
            url.append('?').append(query.entries.joinToString("&") { "${it.key}=${it.value}" })
        }
        return Request.Builder().url(url.toString())
            .header("Authorization", "Bearer $token")
            .header("Client-Id", clientId)
    }

    private fun send(req: Request): JSONObject = http.newCall(req).execute().use { resp ->
        val body = resp.body?.string().orEmpty()
        if (!resp.isSuccessful) {
            // The BODY names the real problem ("missing scope", "invalid OAuth
            // token") and a host can act on that. Trimmed, because a platform
            // can return a page — and it cannot carry a key, because no request
            // in this file sends one.
            throw IllegalStateException("Twitch refused (${resp.code}): ${body.take(300)}")
        }
        if (body.isEmpty()) JSONObject() else JSONObject(body)
    }

    /** The signed-in user's id. Twitch keys every channel call on it. */
    fun broadcasterId(): String {
        val data = send(helix("/users").get().build()).optJSONArray("data") ?: JSONArray()
        val first = data.optJSONObject(0)
            ?: throw IllegalStateException("/users returned no user")
        return first.getString("id")
    }

    /**
     * Title, and category if one resolves. A title change must not fail because
     * the category did — a show going out under the PREVIOUS show's title is a
     * worse outcome than one with no category.
     */
    fun setChannel(broadcasterId: String, title: String, categoryName: String?) {
        val body = JSONObject().put("title", title)
        if (!categoryName.isNullOrEmpty()) {
            runCatching { gameId(categoryName) }.getOrNull()?.let { body.put("game_id", it) }
        }
        send(
            helix("/channels", mapOf("broadcaster_id" to broadcasterId))
                .patch(body.toString().toRequestBody("application/json".toMediaType()))
                .build()
        )
    }

    private fun gameId(name: String): String? =
        send(helix("/games", mapOf("name" to java.net.URLEncoder.encode(name, "UTF-8"))).get().build())
            .optJSONArray("data")?.optJSONObject(0)?.optString("id")?.ifEmpty { null }

    /**
     * The address and the key, fetched once for this show.
     *
     * The title is set BEFORE the key is fetched, deliberately: if the key
     * fetch fails the host has lost nothing, whereas a stream that opens under
     * the last show's title has already misled whoever joined.
     */
    fun prepare(title: String, categoryName: String?): StreamCredentials {
        val id = broadcasterId()
        setChannel(id, title, categoryName)
        val data = send(helix("/streams/key", mapOf("broadcaster_id" to id)).get().build())
            .optJSONArray("data") ?: JSONArray()
        val key = data.optJSONObject(0)?.optString("stream_key")?.ifEmpty { null }
            ?: throw IllegalStateException("/streams/key returned no key")
        val (server, backup) = ingest()
        return StreamCredentials(server = server, key = key, backupServer = backup, broadcasterId = id)
    }

    companion object {
        /**
         * `ingest.twitch.tv/ingests` — the current PoP list, PUBLIC and
         * unauthenticated, whose first entry is Twitch's own "Default"
         * recommendation.
         *
         * Templates arrive as `rtmp://host/app/{stream_key}` and the key is
         * supplied separately, so the placeholder is STRIPPED rather than
         * substituted — a URL with the key in it is exactly what §5 forbids
         * this code from constructing anywhere but the publish call itself.
         *
         * RTMPS on 443 travels through more networks than RTMP on 1935, so the
         * scheme is upgraded. Same rule as Swift.
         */
        fun ingest(): Pair<String, String?> {
            val http = OkHttpClient()
            val req = Request.Builder().url("https://ingest.twitch.tv/ingests").get().build()
            val list = http.newCall(req).execute().use { resp ->
                JSONObject(resp.body?.string().orEmpty()).optJSONArray("ingests") ?: JSONArray()
            }
            fun server(i: Int): String? {
                val t = list.optJSONObject(i)?.optString("url_template")?.ifEmpty { null }
                    ?: return null
                val stripped = t.replace("/{stream_key}", "")
                return if (stripped.startsWith("rtmp://")) {
                    "rtmps://" + stripped.removePrefix("rtmp://")
                } else stripped
            }
            val primary = server(0)
                ?: throw IllegalStateException("no Twitch ingest servers listed")
            return primary to server(1)
        }
    }
}
