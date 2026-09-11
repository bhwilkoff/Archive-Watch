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
        // The file's own name, shown ONLY when the facts above do not tell two
        // copies apart. A multi-reel upload — Buster Keaton Rides Again is
        // reel1.mov and reel2.mov, same size, format and height — otherwise
        // renders as two identical rows, each of them HALF THE FILM. A choice
        // that plays the wrong half is worse than one that cannot play: it
        // looks like it worked.
        val disambiguator: String? = null,
    ) {
        /** `480p · H.264 · 575 MB — Archive derivative` — literal, never "Best". */
        val label: String
            get() {
                val parts = buildList {
                    heightPixels?.takeIf { it > 0 }?.let { add("${it}p") }
                    format.takeIf { it.isNotEmpty() }
                        ?.let { add(it.replace(Regex("h\\.264", RegexOption.IGNORE_CASE), "H.264")) }
                    add(sizeText(sizeBytes))
                    disambiguator?.let { add(it) }
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
                    if (CONTAINERS.none { name.lowercase().endsWith(it) }) continue
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
                val sorted = out.sortedWith(
                    compareByDescending<Version> { it.heightPixels ?: 0 }
                        .thenByDescending { it.sizeBytes },
                )
                // Two copies that render the same label are not a choice.
                val seen = sorted.groupingBy { it.label }.eachCount()
                sorted.map {
                    if ((seen[it.label] ?: 0) > 1) it.copy(disambiguator = stem(it.name)) else it
                }
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
        val name = chosenName(context, archiveID) ?: return playable(fallback)
        return downloadURL(archiveID, name)
    }

    /**
     * Belt-and-braces for a raw archive.org url, matching what Apple's
     * `Catalog.playableURL` and Roku's `AWEncodeSpaces` already do. Every
     * playback path reaches the player through preferredURL, so this is the
     * one place it needs to happen.
     *
     * archive.org filenames routinely contain spaces and `#`. The pipeline
     * encodes them (`remediate_catalog.encode_download_urls`), but it only
     * ever ran over catalog.json — and TV episodes are not catalog items, so
     * 48% of the 4,702 episodes in the spines shipped with raw spaces
     * (measured 2026-09-06, fixed at source the same day). Apple and Roku
     * survived that because they carry this guard; Android had none.
     *
     * Only the two genuinely invalid characters are touched. Parentheses and
     * commas are legal in a url, and existing %XX escapes are left alone so
     * this cannot double-encode.
     */
    fun playable(url: String): String =
        if (!url.contains(' ') && !url.contains('#')) url
        else url.replace(" ", "%20").replace("#", "%23")

    private fun downloadURL(itemID: String, name: String): String {
        val encoded = name.split("/").joinToString("/") {
            URLEncoder.encode(it, "UTF-8").replace("+", "%20")
        }
        return "https://archive.org/download/$itemID/$encoded"
    }

    // Containers Media3 decodes natively. The test used to be `.mp4` only,
    // which is an EXTENSION test standing in for a codec test — and it hid
    // originals ExoPlayer plays perfectly well. A viewer on Reddit
    // (2026-09-11): "it doesn't give you the option to play the full quality
    // original file unless it's h264 (or some other subset)". On Android that
    // was entirely our filter: Media3 ships extractors for Matroska, WebM and
    // the whole MP4/QuickTime family.
    // 
    // Measured over 80 random catalog items, of ~212 ORIGINAL uploads: 138
    // mp4, 46 avi, 12 mpeg, 7 mkv, 6 mov, 2 m4v.
    //
    // AVI IS DELIBERATELY NOT HERE, and this is settled rather than pending.
    // Media3 does ship an AVI extractor, so the container was never the
    // question — the codec inside is. Sampled across 120 catalog items, the
    // .avi originals are 36 Cinepak to 6 DivX: Cinepak is a 1992 codec no
    // Android MediaCodec and no Apple device decodes. Adding AVI would list
    // an option that cannot play for six files in seven, which is the exact
    // dead end this filter exists to prevent. The same measurement rules out
    // .mpeg/.mpg (MPEG-1 and MPEG-2, which few Android devices decode) and
    // Ogg Theora, which Media3 does not support at all.
    private val CONTAINERS = listOf(".mp4", ".mkv", ".webm", ".mov", ".m4v")

    // The file's base name without directory or extension — "reel1" from
    // busterkeatonridesagain/busterkeatonridesagainreel1.mov. Long archive
    // names repeat the item id, which tells the viewer nothing, so the tail is
    // what is kept.
    internal fun stem(name: String): String {
        val base = name.substringAfterLast('/').substringBeforeLast('.')
        if (base.length <= 24) return base
        // Cut at a separator, not mid-token: a bare suffix produced
        // "-38_L001973_FR-B463_H264", which starts inside a word and reads
        // like damage rather than a name.
        val tail = base.takeLast(24)
        val i = tail.indexOfFirst { it == '_' || it == '-' }
        val trimmed = if (i >= 0) tail.substring(i + 1) else tail
        return if (trimmed.length >= 8) trimmed else tail
    }

    private fun sizeText(bytes: Long): String = when {
        bytes >= 1_000_000_000 -> String.format(java.util.Locale.US, "%.1f GB", bytes / 1e9)
        else -> String.format(java.util.Locale.US, "%.0f MB", bytes / 1e6)
    }
}
