package app.archivewatch.android.studio

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * The client half of SHAREPLAY §11 on Android.
 *
 * `HttpURLConnection`, not a library: this project ships no third-party
 * networking (Decision 127's reasoning), and the whole conversation is one
 * GET and one POST of a few hundred bytes.
 *
 * It owns two jobs — keep an estimate of the server's clock, and say what the
 * film should do — and it does NOT touch a player, for the same reason the
 * Swift one does not: a player is ExoPlayer here and `AVPlayer` there, and a
 * type that knew about either could not be tested without it.
 */
class StudioSyncClient(private val base: String = LIVE) {

    companion object {
        /**
         * THE WORKER IS NOT ON archivewatch.org — that host is GitHub Pages.
         * It answers at its own workers.dev origin, the one the privacy
         * counter has always posted to.
         */
        const val LIVE = "https://archivewatch-pulse.benwilkoff.workers.dev"
    }

    sealed class JoinError(message: String) : Exception(message) {
        data object NoSuchRoom : JoinError("no such room")
        data object Ended : JoinError("room ended")
        data object BadCode : JoinError("bad code")
        data class Transport(val why: String) : JoinError(why)
    }

    var code: String? = null
        private set
    var lastState: StudioSync.State? = null
        private set
    /** Returned ONCE at creation; a poll never carries it back (§11.12). */
    private var hostKey: String? = null
    private var clock: StudioSync.ClockSample? = null
    private var generationChangedAt: Long = 0

    val clockOffset: Pair<Double, Double>? get() = clock?.let { it.offset to it.error }

    fun serverNow(): Double =
        System.currentTimeMillis() / 1000.0 + (clock?.offset ?: 0.0)

    suspend fun join(typed: String): StudioSync.State {
        val c = StudioRoom.normalize(typed) ?: throw JoinError.BadCode
        code = c
        return poll()
    }

    fun leave() { code = null; lastState = null; hostKey = null }

    /**
     * One request carries the state AND a clock sample, because they arrive in
     * the same response (§11.6) — measuring the round trip around this very
     * request is what makes the offset free.
     */
    suspend fun poll(): StudioSync.State = withContext(Dispatchers.IO) {
        val c = code ?: throw JoinError.NoSuchRoom
        val sentAt = System.currentTimeMillis() / 1000.0
        val conn = (URL("$base/together/$c").openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 8000
            readTimeout = 8000
        }
        val body = try {
            when (conn.responseCode) {
                404 -> throw JoinError.NoSuchRoom
                410 -> throw JoinError.Ended
                in 200..299 -> conn.inputStream.bufferedReader().readText()
                else -> throw JoinError.Transport("HTTP ${conn.responseCode}")
            }
        } finally { conn.disconnect() }
        val receivedAt = System.currentTimeMillis() / 1000.0

        val o = JSONObject(body)
        val sample = StudioSync.ClockSample(sentAt, o.getDouble("serverTime"), receivedAt)
        // KEEP THE FASTEST, not the newest: a slow exchange's bound is RTT/2,
        // so replacing a 20 ms sample with an 800 ms one makes the clock worse
        // while looking like an update.
        val best = clock
        if (best == null || sample.roundTrip < best.roundTrip) clock = sample

        val state = StudioSync.State(
            filmID = o.getString("filmID"),
            position = o.getDouble("position"),
            atServerTime = o.getDouble("atServerTime"),
            rate = o.optDouble("rate", 1.0),
            paused = o.optBoolean("paused", false),
            generation = o.optInt("generation", 1),
            copy = if (o.isNull("copy")) null else o.optString("copy").ifEmpty { null },
        )
        if (state.generation != lastState?.generation) {
            generationChangedAt = System.currentTimeMillis()
        }
        lastState = state
        state
    }

    fun nextPollDelaySeconds(): Double {
        val quiet = if (generationChangedAt == 0L) 0.0
                    else (System.currentTimeMillis() - generationChangedAt) / 1000.0
        return StudioSync.pollInterval(quiet)
    }

    fun correction(localPosition: Double, localPaused: Boolean): StudioSync.Correction? {
        val s = lastState ?: return null
        return StudioSync.correction(localPosition, localPaused, s, serverNow())
    }

    /** Open a room. The key comes back once and is held, never displayed. */
    suspend fun createRoom(filmID: String, position: Double,
                           rate: Double = 1.0, paused: Boolean = false): String =
        withContext(Dispatchers.IO) {
            val payload = JSONObject(mapOf(
                "filmID" to filmID, "position" to position,
                "rate" to rate, "paused" to paused)).toString()
            val conn = (URL("$base/together/new").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                connectTimeout = 8000
                readTimeout = 8000
            }
            try {
                conn.outputStream.use { it.write(payload.toByteArray()) }
                if (conn.responseCode !in 200..299) throw JoinError.Transport("HTTP ${conn.responseCode}")
                val o = JSONObject(conn.inputStream.bufferedReader().readText())
                code = o.getString("code")
                hostKey = o.optString("hostKey").ifEmpty { null }
                code!!
            } finally { conn.disconnect() }
        }

    /**
     * Publish a state change. Called on play, pause, seek and rate — NEVER on
     * a timer (§11.1), which is what keeps a two-hour film at tens of writes.
     */
    suspend fun publish(filmID: String, position: Double,
                        rate: Double = 1.0, paused: Boolean = false) = withContext(Dispatchers.IO) {
        val c = code ?: throw JoinError.NoSuchRoom
        write(c, JSONObject(mapOf(
            "filmID" to filmID, "position" to position,
            "rate" to rate, "paused" to paused)).toString())
    }

    suspend fun endRoom() = withContext(Dispatchers.IO) {
        val c = code ?: return@withContext
        runCatching { write(c, """{"end":true}""") }
        code = null
        hostKey = null
    }

    /** A joined device saying it is here — an anonymous token, made fresh
     *  per join, tied to nothing; only a COUNT is ever read back (owner,
     *  2026-09-23). Best-effort: a missed ping only makes the count lag. */
    suspend fun sayHere(token: String) = withContext(Dispatchers.IO) {
        val c = code ?: return@withContext
        runCatching {
            val conn = (URL("$base/together/$c/here").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                connectTimeout = 8000
                readTimeout = 8000
            }
            try {
                conn.outputStream.use { it.write(JSONObject(mapOf("token" to token)).toString().toByteArray()) }
                conn.responseCode
            } finally { conn.disconnect() }
        }
    }

    private fun write(c: String, payload: String) {
        val conn = (URL("$base/together/$c").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            // THE CODE IS PUBLIC; THIS IS NOT (§11.12). Without it the write
            // is refused, which is the point.
            hostKey?.let { setRequestProperty("x-aw-host-key", it) }
            connectTimeout = 8000
            readTimeout = 8000
        }
        try {
            conn.outputStream.use { it.write(payload.toByteArray()) }
            if (conn.responseCode !in 200..299) throw JoinError.Transport("HTTP ${conn.responseCode}")
            conn.inputStream.bufferedReader().readText()
        } finally { conn.disconnect() }
    }
}
