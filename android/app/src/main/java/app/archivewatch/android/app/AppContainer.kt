package app.archivewatch.android.app

import android.app.Application
import app.archivewatch.android.BuildConfig
import app.archivewatch.android.data.CatalogRepository
import app.archivewatch.android.data.ClipExporter
import app.archivewatch.android.data.EditorialRepository
import app.archivewatch.android.data.SettingsStore
import app.archivewatch.android.data.SubtitleAccountStore
import app.archivewatch.android.data.UserStateStore
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/** Manual DI — created once by the Application; passed down via AppRoot. */
class AppContainer(private val application: Application) {

    // A real User-Agent is REQUIRED on every archive.org request: its main host
    // rate-limits/blocks UA-less bursts, and most poster/cover URLs 302 through
    // that host. Without this, Coil's poster bursts get 403/429/reset and fall
    // back to title cards — the Android analog of the iOS -1004 storm. Shared by
    // Coil (images), catalog refresh, and editorial fetches.
    val okHttp: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .addInterceptor { chain ->
            chain.proceed(
                chain.request().newBuilder()
                    .header(
                        "User-Agent",
                        "ArchiveWatch-Android/${BuildConfig.VERSION_NAME} (+https://archivewatch.org)",
                    )
                    .build(),
            )
        }
        .build()

    val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
        explicitNulls = false
    }

    val settings = SettingsStore(application)
    // Lazy: nothing on the launch path touches it, and its Keystore setup was
    // running before Home could draw.
    val subtitleAccount by lazy { SubtitleAccountStore(application) }
    val userState = UserStateStore(application)
    /**
     * The catalog download gets its OWN client, not the shared one.
     *
     * `okHttp` is also Coil's image loader, so at launch the 41 MB catalog was
     * competing with a burst of poster fetches for the same dispatcher,
     * connection pool and TLS budget on a weak TV CPU. Measured on the Google
     * TV: the app took 13.0s for a file that `curl` pulls in 2.2s on the same
     * device over the same wifi — a 6x gap that is contention, not bandwidth
     * (the link negotiates 650 Mbps and curl sustained 19.2 MB/s).
     *
     * A separate client means a separate Dispatcher and ConnectionPool, so the
     * one download the viewer is actually waiting for is not queued behind
     * fifty thumbnails.
     */
    private val catalogHttp: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .addInterceptor { chain ->
            chain.proceed(
                chain.request().newBuilder()
                    .header(
                        "User-Agent",
                        "ArchiveWatch-Android/${BuildConfig.VERSION_NAME} (+https://archivewatch.org)",
                    )
                    .build(),
            )
        }
        .build()

    val catalog = CatalogRepository(application, catalogHttp, json)
    val editorial = EditorialRepository(application, okHttp, json)
    val clipExporter by lazy { ClipExporter(application, okHttp) }

    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** Launch order: seed open (fast) → settings filters → full-DB refresh. */
    fun start() {
        scope.launch {
            catalog.initialize()
            catalog.applyFilters(settings.hideAdultContent.first(), settings.hiddenCategories.first())
            catalog.refresh()
        }
        observeForeground()
    }

    /**
     * Re-check the catalog whenever the app comes to the foreground. Without
     * this, [start] is the ONLY caller of refresh — so a process Android kept
     * alive across days of non-use kept serving its cold-start catalog and the
     * user saw stale shelves forever. Throttled by the repository's TTL, and
     * the UI re-queries automatically off the dbVersion bump.
     */
    private fun observeForeground() {
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) {
                scope.launch { catalog.refreshIfStale() }
            }
        })
    }
}
