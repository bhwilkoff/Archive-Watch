package app.archivewatch.android.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.withLock
import app.archivewatch.android.BuildConfig
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
        /** How long a check stays fresh before a foreground resume re-checks. */
        const val DEFAULT_STALE_AFTER_MS = 6L * 60 * 60 * 1000
    }

    private val dbFile: File get() = File(context.filesDir, "catalog.sqlite")
    private val etagFile: File get() = File(context.filesDir, "catalog.etag")
    private val lastCheckFile: File get() = File(context.filesDir, "catalog.lastcheck")

    @Volatile var db: CatalogDatabase? = null
        private set

    private val _dbVersion = MutableStateFlow(0)
    val dbVersion: StateFlow<Int> = _dbVersion

    @Volatile private var hideAdult = true
    @Volatile private var hiddenTypes: Set<String> = emptySet()

    /**
     * Suspends until the catalog is open. A screen's data producer must never
     * bail on a momentarily-null [db]: produceState runs once per key change,
     * so an early return during startup or the refresh swap leaves that
     * screen's value null FOREVER — a spinner that never resolves (measured
     * on the Google TV device, Channels tab, 2026-08-27).
     */
    suspend fun awaitDb(): CatalogDatabase {
        db?.let { return it }
        dbVersion.first { db != null }
        return db!!
    }

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

    /** True when the release hasn't been checked for a newer DB within [ttlMillis]. */
    fun isStale(ttlMillis: Long = DEFAULT_STALE_AFTER_MS): Boolean {
        val last = lastCheckFile.takeIf { it.exists() }?.readText()?.trim()?.toLongOrNull()
            ?: return true
        return System.currentTimeMillis() - last >= ttlMillis
    }

    /**
     * Foreground/resume path. [refresh] runs once from Application.onCreate, so
     * a process kept alive for days served its cold-start catalog forever.
     * Throttled by [ttlMillis]; a no-op when the release is unchanged.
     */
    suspend fun refreshIfStale(ttlMillis: Long = DEFAULT_STALE_AFTER_MS) {
        if (!isStale(ttlMillis)) return
        refresh()
    }

    /**
     * Guards against a SECOND refresh while one is already running.
     *
     * `start()` fires a refresh, and ProcessLifecycle's onStart fires
     * `refreshIfStale()` — on a cold launch BOTH happen, so the app ran two
     * concurrent 41 MB downloads and wrote the 149 MB database TWICE to the
     * same slow flash. Instrumentation caught it: `refresh:enter` and
     * `http:call` each appeared twice in one launch. It is also why the app
     * downloaded at ~4 MB/s where curl sustains 20 on the same device — the
     * two streams were competing with each other, not with the network.
     */
    private val refreshMutex = kotlinx.coroutines.sync.Mutex()
    @Volatile private var refreshInFlight = false

    /** ETag-conditional download → inflate → validate → atomic swap. */
    suspend fun refresh() {
        // A second caller returns immediately rather than queueing: by the time
        // the first finishes, its result is exactly what the second wanted.
        if (refreshInFlight) return
        refreshMutex.withLock {
            if (refreshInFlight) return
            refreshInFlight = true
            try { refreshInner() } finally { refreshInFlight = false }
        }
    }

    private suspend fun refreshInner() = withContext(Dispatchers.IO) {
        // Load-path timing, debug builds only. It is what found the duplicate
        // refresh: `refresh:enter` appeared TWICE in one cold launch.
        val t0 = android.os.SystemClock.elapsedRealtime()
        fun mark(what: String) {
            if (BuildConfig.DEBUG) android.util.Log.i(
                "AWLOAD", "$what +${android.os.SystemClock.elapsedRealtime() - t0}ms")
        }
        mark("refresh:enter")
        try {
            val builder = Request.Builder().url(ZZ_URL)
            val etag = etagFile.takeIf { it.exists() }?.readText()?.trim()
            if (!etag.isNullOrEmpty()) builder.header("If-None-Match", etag)

            mark("http:call")
            okHttp.newCall(builder.build()).execute().use { response ->
                mark("http:headers")
                // A completed round trip counts as a check even when unchanged,
                // so the TTL throttles re-checks rather than re-downloads.
                lastCheckFile.writeText(System.currentTimeMillis().toString())
                if (response.code == 304) return@withContext
                if (!response.isSuccessful) return@withContext
                val body = response.body ?: return@withContext

                // STREAMED: inflate straight off the socket into staging, so the
                // compressed copy is never written to disk at all.
                //
                // The TV's flash — not its network — is the constraint. Measured
                // on the Google TV: raw write is 9.4 MB/s (150 MB takes 15.8s),
                // while curl pulls this file to a FILE on that same flash at
                // 20 MB/s. First run used to write 190 MB: the 41 MB .zz, then
                // the 149 MB inflated DB. Not landing the .zz removes 41 MB of
                // writes AND overlaps the inflate with the download instead of
                // running it afterwards.
                val staging = File(context.filesDir, "catalog.sqlite.staging")
                try {
                    inflateRawDeflate(body.byteStream(), staging)
                    mark("inflate:done")
                    if (staging.length() < MIN_VALID_BYTES) return@withContext

                    // Open probe — meta.itemCount must exist (§9.5).
                    val probe = CatalogDatabase.open(staging.path, json) ?: return@withContext
                    probe.close()
                    mark("probe:done")

                    val old = db
                    if (!staging.renameTo(dbFile)) return@withContext
                    swap(CatalogDatabase.open(dbFile.path, json))
                    mark("swap:done")
                    old?.close()

                    // Store the new ETag only after the swap (§9.4).
                    response.header("ETag")?.let { etagFile.writeText(it) }
                } finally {
                    staging.delete()
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
    private fun inflateRawDeflate(src: java.io.InputStream, dst: File) {
        val inflater = Inflater(true)
        try {
            src.use { input ->
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
