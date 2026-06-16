package app.archivewatch.android.app

import android.app.Application
import app.archivewatch.android.data.CatalogRepository
import app.archivewatch.android.data.ClipExporter
import app.archivewatch.android.data.EditorialRepository
import app.archivewatch.android.data.SettingsStore
import app.archivewatch.android.data.UserStateStore
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

    val okHttp: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
        explicitNulls = false
    }

    val settings = SettingsStore(application)
    val userState = UserStateStore(application)
    val catalog = CatalogRepository(application, okHttp, json)
    val editorial = EditorialRepository(application, okHttp, json)
    val clipExporter = ClipExporter(application, okHttp)

    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** Launch order: seed open (fast) → settings filters → full-DB refresh. */
    fun start() {
        scope.launch {
            catalog.initialize()
            catalog.applyFilters(settings.hideAdultContent.first())
            catalog.refresh()
        }
    }
}
