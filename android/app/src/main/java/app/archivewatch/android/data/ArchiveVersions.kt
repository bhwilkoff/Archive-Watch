package app.archivewatch.android.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.net.URLEncoder

/**
 * Every playable copy of a film on its archive.org item, so the VIEWER can
 * choose (the tvOS ArchiveVersions service, ported — owner 2026-08-17:
 * "providing the user with the ability to select themselves from the
 * different video … available for each title").
 *
 * Fetched ON DEMAND when the picker opens, never at Detail load — the file
 * list is exactly what /metadata returns, so it needs no catalog column and
 * cannot go stale. The choice is stored per-title by file NAME (device-local,
 * deliberately unsynced: the right copy depends on this screen and this
 * network), and the play URL is rebuilt deterministically so honouring a
 * choice never needs the network.
 */
object ArchiveVersions {

    data class Version(
        val name: String,
        val url: String,
        val sizeBytes: Long,
        val format: String,
        val heightPixels: Int?,
        val isDerivative: Boolean,
    ) {
        /** `480p · H.264 · 575 MB — Archive derivative` — literal, never "Best". */
        val label: String
            get() {
                val parts = buildList {
                    heightPixels?.takeIf { it > 0 }?.let { add("${it}p") }
                    format.takeIf { it.isNotEmpty() }
                        ?.let { add(it.replace(Regex("h\\.264", RegexOption.IGNORE_CASE), "H.264")) }
                    add(sizeText(sizeBytes))
                }
                val origin = if (isDerivative) "Archive derivative" else "uploader original"
                return parts.joinToString(" · ") + " — " + origin
            }
    }

    private val http = OkHttpClient()

    /** Playable video copies on the item, best quality first (resolution,
     *  then size as the tiebreak — bytes measure the encoder, not the
     *  transfer: a 240p MPEG-4 can outweigh a 480p H.264). */
    suspend fun list(itemID: String): List<Version> = withContext(Dispatchers.IO) {
        runCatching {
            val req = Request.Builder()
                .url("https://archive.org/metadata/$itemID")
                .build()
            http.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext emptyList()
                val files = JSONObject(resp.body?.string() ?: return@withContext emptyList())
                    .optJSONArray("files") ?: return@withContext emptyList()
                val out = mutableListOf<Version>()
                for (i in 0 until files.length()) {
                    val f = files.optJSONObject(i) ?: continue
                    val name = f.optString("name")
                    if (!name.lowercase().endsWith(".mp4")) continue
                    val size = f.optString("size").toLongOrNull() ?: continue
                    if (size <= 5_000_000) continue     // a stub, a sample, or a thumbnail
                    out.add(
                        Version(
                            name = name,
                            url = downloadURL(itemID, name),
                            sizeBytes = size,
                            format = f.optString("format"),
                            heightPixels = f.optString("height").toIntOrNull(),
                            isDerivative = f.optString("source") == "derivative",
                        ),
                    )
                }
                out.sortedWith(
                    compareByDescending<Version> { it.heightPixels ?: 0 }
                        .thenByDescending { it.sizeBytes },
                )
            }
        }.getOrDefault(emptyList())
    }

    // MARK: per-title choice (SharedPreferences map, name-keyed)

    private const val PREFS = "aw.versionChoice"

    fun chosenName(context: Context, archiveID: String): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(archiveID, null)

    fun choose(context: Context, archiveID: String, version: Version?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
            if (version == null) remove(archiveID) else putString(archiveID, version.name)
        }.apply()
    }

    /** The URL to actually play: the viewer's choice when made, else the
     *  pipeline's pick unchanged. Rebuilt from the stored NAME so honouring
     *  a choice never waits on /metadata. */
    fun preferredURL(context: Context, archiveID: String, fallback: String): String {
        val name = chosenName(context, archiveID) ?: return fallback
        return downloadURL(archiveID, name)
    }

    private fun downloadURL(itemID: String, name: String): String {
        val encoded = name.split("/").joinToString("/") {
            URLEncoder.encode(it, "UTF-8").replace("+", "%20")
        }
        return "https://archive.org/download/$itemID/$encoded"
    }

    private fun sizeText(bytes: Long): String = when {
        bytes >= 1_000_000_000 -> String.format(java.util.Locale.US, "%.1f GB", bytes / 1e9)
        else -> String.format(java.util.Locale.US, "%.0f MB", bytes / 1e6)
    }
}
