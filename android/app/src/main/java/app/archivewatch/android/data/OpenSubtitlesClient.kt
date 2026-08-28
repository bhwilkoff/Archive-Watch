package app.archivewatch.android.data

import android.content.Context
import app.archivewatch.android.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.nio.charset.Charset

/**
 * OpenSubtitles with the VIEWER'S OWN free account — the iOS
 * OpenSubtitlesClient, ported (see that file's header for why this shape:
 * the download QUOTA follows the USER's account; the request RATE follows
 * the shared API key, so 429 is a transient pause, never an error).
 *
 * Matching is by IMDb id, never title — the Decision-026 failure class
 * (a subtitle for a different film or cut) is exactly what title search
 * reintroduces. Credentials live in EncryptedSharedPreferences (the
 * Keychain analogue), never in the catalog or plain prefs.
 */
object OpenSubtitlesClient {

    private const val HOST = "https://api.opensubtitles.com/api/v1"
    private val http = OkHttpClient()
    private val JSON = "application/json".toMediaType()

    val isAvailable: Boolean get() = BuildConfig.OPENSUBTITLES_API_KEY.isNotEmpty()

    data class Match(
        val fileID: Int,
        val language: String,
        val downloadCount: Int,
        val fromTrusted: Boolean,
        val hearingImpaired: Boolean,
        val releaseName: String,
    )

    data class Quota(val allowed: Int, val remaining: Int, val level: String)

    class SubsException(message: String, val quotaSpent: Boolean = false) : Exception(message)

    // ---- pure logic (mirrors the Swift + its unit tests) ----

    fun searchPath(imdbID: String, language: String = "en"): String? {
        val raw = imdbID.removePrefix("tt")
        val n = raw.toIntOrNull() ?: return null
        return "$HOST/subtitles?imdb_id=$n&languages=$language" +
            "&order_by=download_count&order_direction=desc"
    }

    /** Trusted first, then download count; hearing-impaired LAST, not dropped. */
    fun best(matches: List<Match>): Match? = matches.maxWithOrNull(
        compareBy({ if (it.hearingImpaired) 0 else 1 },
                  { if (it.fromTrusted) 1 else 0 },
                  { it.downloadCount }),
    )

    fun parseMatches(body: String): List<Match> = runCatching {
        val items = JSONObject(body).optJSONArray("data") ?: return emptyList()
        buildList {
            for (i in 0 until items.length()) {
                val attrs = items.optJSONObject(i)?.optJSONObject("attributes") ?: continue
                val fid = attrs.optJSONArray("files")?.optJSONObject(0)
                    ?.optInt("file_id", -1) ?: -1
                if (fid <= 0) continue
                add(Match(
                    fileID = fid,
                    language = attrs.optString("language", "en"),
                    downloadCount = attrs.optInt("download_count", 0),
                    fromTrusted = attrs.optBoolean("from_trusted", false),
                    hearingImpaired = attrs.optBoolean("hearing_impaired", false),
                    releaseName = attrs.optString("release", ""),
                ))
            }
        }
    }.getOrDefault(emptyList())

    /** SRT -> WebVTT; the comma decimal separator is the #1 render-nothing bug. */
    fun srtToVtt(srt: String): String {
        var body = srt.replace("\r\n", "\n").replace("\r", "\n")
            .trim('﻿', '\n', ' ')
        body = body.replace(Regex("(\\d{1,2}:\\d{2}:\\d{2}),(\\d{1,3})"), "$1.$2")
        return "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000\n\n" + body + "\n"
    }

    /** BOM first, NUL-heavy body as UTF-16, then UTF-8, then cp1252. */
    fun decode(bytes: ByteArray): String {
        if (bytes.size >= 2) {
            if (bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte())
                return String(bytes, Charsets.UTF_16LE)
            if (bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte())
                return String(bytes, Charsets.UTF_16BE)
            if (bytes.size >= 3 && bytes[0] == 0xEF.toByte() &&
                bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte())
                return String(bytes, 3, bytes.size - 3, Charsets.UTF_8)
        }
        if (bytes.take(400).count { it == 0.toByte() } > 40)
            return String(bytes, Charsets.UTF_16LE)
        return runCatching { String(bytes, Charsets.UTF_8) }
            .getOrElse { String(bytes, Charset.forName("windows-1252")) }
    }

    // ---- networked ----

    private fun request(url: String, token: String?, method: String = "GET",
                        body: String? = null): Request {
        val b = Request.Builder().url(url)
            .header("Api-Key", BuildConfig.OPENSUBTITLES_API_KEY)
            .header("Content-Type", "application/json")
            // OpenSubtitles rejects generic User-Agents.
            .header("User-Agent", "ArchiveWatch v" + BuildConfig.VERSION_NAME)
        token?.let { b.header("Authorization", "Bearer $it") }
        if (method == "POST") b.post((body ?: "{}").toRequestBody(JSON))
        return b.build()
    }

    /** One request, retrying 429 with backoff (the shared-key throughput cap). */
    private suspend fun send(req: Request, tries: Int = 3): Pair<Int, String> {
        var attempt = 0
        while (true) {
            val (code, body, retryAfter) = withContext(Dispatchers.IO) {
                http.newCall(req).execute().use {
                    Triple(it.code, it.body?.string() ?: "", it.header("Retry-After"))
                }
            }
            if (code != 429 || attempt >= tries - 1) return code to body
            delay(((retryAfter?.toDoubleOrNull() ?: 1.5) * 1000).toLong())
            attempt++
        }
    }

    data class Session(val token: String, val quota: Quota?, val obtained: Long = System.currentTimeMillis()) {
        val isFresh: Boolean get() = System.currentTimeMillis() - obtained < 20 * 3600_000L
    }

    private fun parseQuota(j: JSONObject): Quota? {
        val u = j.optJSONObject("user") ?: return null
        val allowed = u.optInt("allowed_downloads", 0)
        return Quota(allowed, u.optInt("remaining_downloads", allowed),
                     u.optString("level", "Free"))
    }

    suspend fun login(username: String, password: String): Session {
        val body = JSONObject(mapOf("username" to username, "password" to password)).toString()
        val (code, resp) = send(request("$HOST/login", null, "POST", body))
        val j = runCatching { JSONObject(resp) }.getOrNull()
        val token = j?.optString("token").takeUnless { it.isNullOrEmpty() }
        if (code != 200 || token == null) {
            // Surface what the SERVER said — it is specific ("remember to use
            // your username and not your email") and actionable.
            val server = j?.optString("message").orEmpty().trim()
            throw SubsException(
                if (server.isNotEmpty()) "OpenSubtitles sign-in failed: $server"
                else if (code == 401) "OpenSubtitles sign-in failed: check your username and password"
                else "OpenSubtitles sign-in failed (HTTP $code)",
            )
        }
        return Session(token, j?.let { parseQuota(it) })
    }

    /** Best English subtitle for an IMDb id, saved as WebVTT; returns the file. */
    suspend fun fetchVTT(context: Context, imdbID: String, token: String, archiveID: String): File {
        val search = searchPath(imdbID) ?: throw SubsException("No subtitles found for this title.")
        val (_, body) = send(request(search, token))
        val pick = best(parseMatches(body))
            ?: throw SubsException("No subtitles found for this title.")
        val dlBody = JSONObject(mapOf("file_id" to pick.fileID)).toString()
        val (code, dResp) = send(request("$HOST/download", token, "POST", dlBody))
        when (code) {
            406 -> throw SubsException(
                "You've used today's OpenSubtitles downloads.", quotaSpent = true)
            429 -> throw SubsException("OpenSubtitles is busy — try again in a moment.")
        }
        val link = runCatching { JSONObject(dResp).optString("link") }.getOrNull()
            .takeUnless { it.isNullOrEmpty() }
            ?: throw SubsException("Download failed (HTTP $code)")
        val bytes = withContext(Dispatchers.IO) {
            http.newCall(Request.Builder().url(link).build()).execute().use {
                it.body?.bytes() ?: ByteArray(0)
            }
        }
        val text = decode(bytes)
        if (text.isBlank()) throw SubsException("No subtitles found for this title.")
        val dir = File(context.cacheDir, "subs").apply { mkdirs() }
        val out = File(dir, "$archiveID.vtt")
        out.writeText(srtToVtt(text))
        return out
    }

    /** A previously downloaded track for this title, if any. */
    fun cachedVTT(context: Context, archiveID: String): File? =
        File(File(context.cacheDir, "subs"), "$archiveID.vtt").takeIf { it.exists() && it.length() > 40 }
}
