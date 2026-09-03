package app.archivewatch.android.app

import android.app.Application
import android.util.Log
import app.archivewatch.android.BuildConfig
import coil3.EventListener
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.ErrorResult
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.crossfade
import okio.Path.Companion.toOkioPath

/**
 * Composition root — manual DI via [AppContainer] (no Hilt in the v1
 * spine). Coil shares the container's OkHttpClient so one connection
 * pool serves images, JSON, and the catalog download.
 */
class ArchiveWatchApplication : Application(), SingletonImageLoader.Factory {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        container.start()
    }

    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .components {
                add(OkHttpNetworkFetcherFactory(callFactory = { container.okHttp }))
            }
            .memoryCache {
                MemoryCache.Builder().maxSizeBytes(60L * 1024 * 1024).build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("image_cache").toOkioPath())
                    .maxSizeBytes(500L * 1024 * 1024)
                    .build()
            }
            .crossfade(true)
            .apply { if (BuildConfig.DEBUG) eventListener(ImageTiming) }
            .build()

    /**
     * Debug-only instrument: how long each artwork request takes from start to
     * paint, tagged AWIMG in logcat. The owner reported Home rendering in a
     * couple of seconds while posters trailed by ~10s; this is what measures
     * it (screenshots proved unreliable for timing on this device).
     */
    private object ImageTiming : EventListener() {
        private val started = java.util.concurrent.ConcurrentHashMap<ImageRequest, Long>()
        override fun onStart(request: ImageRequest) {
            started[request] = android.os.SystemClock.elapsedRealtime()
        }
        override fun onSuccess(request: ImageRequest, result: SuccessResult) {
            val t0 = started.remove(request) ?: return
            Log.i("AWIMG", "ok ${android.os.SystemClock.elapsedRealtime() - t0}ms " +
                "${result.dataSource} ${request.data}")
        }
        override fun onError(request: ImageRequest, result: ErrorResult) {
            val t0 = started.remove(request) ?: return
            Log.i("AWIMG", "err ${android.os.SystemClock.elapsedRealtime() - t0}ms " +
                "${result.throwable.javaClass.simpleName} ${request.data}")
        }
    }
}
