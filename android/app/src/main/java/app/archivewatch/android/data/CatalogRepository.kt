package app.archivewatch.android.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.zip.Inflater

/**
 * Owns the catalog DB lifecycle per docs/CATALOG-CONTRACT.md §2/§4/§9:
 * bundled seed.sqlite for instant first paint → cached full DB →
 * freshly downloaded DB (raw-DEFLATE `.zz`, ETag-conditional GET,
 * staging-file inflate, 10 MB size floor, open probe, atomic swap).
 * UI re-queries on every [dbVersion] bump.
 */
class CatalogRepository(
    private val context: Context,
    private val okHttp: OkHttpClient,
    private val json: Json,
) {
    companion object {
        private const val ZZ_URL =
            "https://github.com/bhwilkoff/Archive-Watch/releases/download/catalog-db/catalog.sqlite.zz"
        private const val MIN_VALID_BYTES = 10_000_000L
        private const val SEED_ASSET = "seed.sqlite"
    }

    private val dbFile: File get() = File(context.filesDir, "catalog.sqlite")
    private val etagFile: File get() = File(context.filesDir, "catalog.etag")

    @Volatile var db: CatalogDatabase? = null
        private set

    private val _dbVersion = MutableStateFlow(0)
    val dbVersion: StateFlow<Int> = _dbVersion

    @Volatile private var hideAdult = true
    @Volatile private var hiddenTypes: Set<String> = emptySet()

    /** Seed copy + open. Call once at launch before any query. */
    suspend fun initialize() = withContext(Dispatchers.IO) {
        if (!dbFile.exists()) copySeed()
        var opened = CatalogDatabase.open(dbFile.path, json)
        if (opened == null) {
            // Corrupt cache — fall back to the bundled seed (the floor state).
            dbFile.delete()
            etagFile.delete()
            copySeed()
            opened = CatalogDatabase.open(dbFile.path, json)
        }
        swap(opened)
    }

    /**
     * Decision 012 default-deny + hidden categories: baked into the DB
     * layer once so every query is filtered at the source.
     */
    fun applyFilters(hideAdultContent: Boolean, hidden: Set<String> = emptySet()) {
        hideAdult = hideAdultContent
        hiddenTypes = hidden
        db?.let {
            it.hideAdult = hideAdultContent
            it.hiddenTypes = hidden
        }
        _dbVersion.value += 1
    }

    /** ETag-conditional download → inflate → validate → atomic swap. */
    suspend fun refresh() = withContext(Dispatchers.IO) {
        try {
            val builder = Request.Builder().url(ZZ_URL)
            val etag = etagFile.takeIf { it.exists() }?.readText()?.trim()
            if (!etag.isNullOrEmpty()) builder.header("If-None-Match", etag)

            okHttp.newCall(builder.build()).execute().use { response ->
                if (response.code == 304) return@withContext
                if (!response.isSuccessful) return@withContext
                val body = response.body ?: return@withContext

                val zz = File(context.cacheDir, "catalog.sqlite.zz")
                zz.outputStream().use { out -> body.byteStream().copyTo(out, 64 * 1024) }

                // Inflate to a staging file, never over the live DB (§9).
                val staging = File(context.filesDir, "catalog.sqlite.staging")
                try {
                    inflateRawDeflate(zz, staging)
                    if (staging.length() < MIN_VALID_BYTES) return@withContext

                    // Open probe — meta.itemCount must exist (§9.5).
                    val probe = CatalogDatabase.open(staging.path, json) ?: return@withContext
                    probe.close()

                    val old = db
                    if (!staging.renameTo(dbFile)) return@withContext
                    swap(CatalogDatabase.open(dbFile.path, json))
                    old?.close()

                    // Store the new ETag only after the swap (§9.4).
                    response.header("ETag")?.let { etagFile.writeText(it) }
                } finally {
                    staging.delete()
                    zz.delete()
                }
            }
        } catch (_: Throwable) {
            // Any failure keeps the cached DB (§9.1).
        }
    }

    private fun swap(newDb: CatalogDatabase?) {
        newDb?.hideAdult = hideAdult
        newDb?.hiddenTypes = hiddenTypes
        db = newDb
        _dbVersion.value += 1
    }

    private fun copySeed() {
        context.assets.open(SEED_ASSET).use { input ->
            dbFile.outputStream().use { output -> input.copyTo(output, 64 * 1024) }
        }
    }

    /**
     * Raw DEFLATE (RFC 1951) per contract §4 — `Inflater(nowrap = true)`,
     * streamed file→file in 64 KB chunks.
     */
    private fun inflateRawDeflate(src: File, dst: File) {
        val inflater = Inflater(true)
        try {
            src.inputStream().use { input ->
                dst.outputStream().use { out ->
                    val inBuf = ByteArray(64 * 1024)
                    val outBuf = ByteArray(64 * 1024)
                    while (!inflater.finished()) {
                        if (inflater.needsInput()) {
                            val n = input.read(inBuf)
                            if (n == -1) break
                            inflater.setInput(inBuf, 0, n)
                        }
                        while (true) {
                            val written = inflater.inflate(outBuf)
                            if (written > 0) out.write(outBuf, 0, written) else break
                        }
                    }
                }
            }
            check(inflater.finished()) { "truncated DEFLATE stream" }
        } finally {
            inflater.end()
        }
    }
}
