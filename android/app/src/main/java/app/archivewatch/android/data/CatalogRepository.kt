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
        /** A television box is the slowest thing we run on, and publishing several
         *  times a day meant a full download on nearly every evening's launch. */
        const val TV_STALE_AFTER_MS = 24L * 60 * 60 * 1000
        /** Launch is the busiest moment: Home's queries, its posters and first
         *  composition. A catalog that already works can wait until they are done. */
        const val SETTLE_AFTER_LAUNCH_MS = 45_000L
        const val METERED_MAX_AGE_MS = 7L * 24 * 60 * 60 * 1000
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
        // A read that proves the open DB is corrupt discards the DOWNLOADED
        // file, so the next launch re-downloads and the bundled seed serves in
        // the meantime. The open-probe cannot catch this: it reads pages near
        // the start of the file, and a truncated or torn download is corrupt
        // further in — which is how "database disk image is malformed" became
        // the app's second-largest crash cluster with a clean open before it.
        CatalogDatabase.onCorruption = {
            runCatching {
                dbFile.delete()
                etagFile.delete()   // or the next request 304s and keeps it away
            }
        }
        if (pendingFile.exists() && pendingFile.renameTo(dbFile)) {
            pendingEtagFile.takeIf { it.exists() }?.let { it.copyTo(etagFile, overwrite = true); it.delete() }
        }
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
        if (!isStale(ttlMillis) || pendingFile.exists()) return
        // A device with no downloaded catalog has only the seed, and needs it now.
        if (etagFile.exists()) {
            kotlinx.coroutines.delay(SETTLE_AFTER_LAUNCH_MS)
            if (!isStale(ttlMillis)) return
        }
        refresh()
    }

    /** Set by the app's lifecycle. A new catalog is not swapped in under a viewer. */
    @Volatile var onScreen = true

    /**
     * Swapping rebuilds Home: every shelf re-queried and recomposed. On a TV box
     * that ran over a viewer's key presses and made them ANRs (Play vitals,
     * 2026-11: 21 of 22 on Android 14 boxes, most with a refresh in flight). So a
     * finished download waits here until the app is off screen, or the next launch.
     */
    private val pendingFile: File get() = File(context.filesDir, "catalog.sqlite.next")
    private val pendingEtagFile: File get() = File(context.filesDir, "catalog.next.etag")

    suspend fun applyPending() = withContext(Dispatchers.IO) {
        refreshMutex.withLock { swapInPending() }
    }

    private suspend fun swapInPending() {
        if (!pendingFile.exists()) return
        val old = db
        if (!pendingFile.renameTo(dbFile)) return
        swap(CatalogDatabase.open(dbFile.path, json))
        old?.closeWhenIdle()
        pendingEtagFile.takeIf { it.exists() }?.let { it.copyTo(etagFile, overwrite = true); it.delete() }
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

    private fun isMetered(): Boolean = try {
        (context.getSystemService(Context.CONNECTIVITY_SERVICE)
            as android.net.ConnectivityManager).isActiveNetworkMetered
    } catch (_: Throwable) {
        false
    }

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
        // At normal priority the inflate and its writes took the CPU from a weak
        // box's main thread. All of that work is blocking, on this one thread.
        val tid = android.os.Process.myTid()
        val priorPriority = android.os.Process.getThreadPriority(tid)
        android.os.Process.setThreadPriority(tid, android.os.Process.THREAD_PRIORITY_BACKGROUND)
        try {
            refreshBlocking()
        } finally {
            android.os.Process.setThreadPriority(tid, priorPriority)
        }
    }

    private suspend fun refreshBlocking() {
        // Load-path timing, debug builds only. It is what found the duplicate
        // refresh: `refresh:enter` appeared TWICE in one cold launch.
        val t0 = android.os.SystemClock.elapsedRealtime()
        fun mark(what: String) {
            if (BuildConfig.DEBUG) android.util.Log.i(
                "AWLOAD", "$what +${android.os.SystemClock.elapsedRealtime() - t0}ms")
        }
        mark("refresh:enter")
        // On a METERED network, keep a catalog that is less than a week old.
        // The pipeline publishes several times a day, so an unconditional
        // refresh on launch pulled a fresh 41 MB almost every time the app
        // opened — a viewer on a capped mobile plan: "it eats up all my data
        // before I can even press play" (r/classicfilms, 2026-09-12). Wi-Fi
        // behaves as before, and a device with no catalog always downloads.
        if (isMetered() && dbFile.exists() &&
            System.currentTimeMillis() - dbFile.lastModified() < METERED_MAX_AGE_MS
        ) {
            mark("refresh:skip-metered")
            return
        }
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
                if (response.code == 304) return
                if (!response.isSuccessful) return
                val body = response.body

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
                    if (staging.length() < MIN_VALID_BYTES) return

                    // Open probe — meta.itemCount must exist (§9.5).
                    val probe = CatalogDatabase.open(staging.path, json) ?: return
                    probe.close()
                    mark("probe:done")

                    // Under a viewer, it waits (see pendingFile). The seed is
                    // replaced at once: that is the wait the viewer is in.
                    if (onScreen && etagFile.exists()) {
                        if (!staging.renameTo(pendingFile)) return
                        response.header("ETag")?.let { pendingEtagFile.writeText(it) }
                        mark("swap:deferred")
                        return
                    }
                    val old = db
                    if (!staging.renameTo(dbFile)) return
                    swap(CatalogDatabase.open(dbFile.path, json))
                    mark("swap:done")
                    old?.closeWhenIdle()

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
        ArchiveVersions.mergedIDs = newDb?.let { d ->
            val lookup: suspend (String) -> List<String> = { id -> d.mergedIDs(id) }
            lookup
        }
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
