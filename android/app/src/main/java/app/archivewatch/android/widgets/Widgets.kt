package app.archivewatch.android.widgets

import android.content.Context
import androidx.core.content.edit
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import androidx.core.graphics.scale
import androidx.core.net.toUri
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.app.ArchiveWatchApplication
import app.archivewatch.android.data.CatalogItem
import okhttp3.Request
import java.util.Calendar

/**
 * Home-screen widgets — the iOS WidgetKit suite's analogue (PARITY §8):
 * Continue Watching (your own resume state), Pick of the Day (the same
 * date-seeded editorial pick every device shows today), and Surprise Me
 * (one tap, one random film). Each deep-links into the app; nothing here
 * is a recommendation model's opinion (TV-DESIGN §1.4 spirit).
 */

private fun deepLink(context: Context, uri: String): Intent =
    Intent(Intent.ACTION_VIEW, uri.toUri()).setPackage(context.packageName)

// IO dispatcher: Glance calls provideGlance on the MAIN thread, and the
// blocking read threw NetworkOnMainThreadException there — swallowed, so no
// widget had ever shown a poster (seen on the Pixel's home screen, 2026-09-29).
// The app's SHARED client: a bare OkHttpClient sent no User-Agent, and
// Wikimedia refuses that with a 403 (The Terror's Commons poster never drew).
private suspend fun fetchPoster(context: Context, url: String?): Bitmap? = url?.let { withContext(Dispatchers.IO) {
    runCatching {
        (context.applicationContext as ArchiveWatchApplication).container.okHttp.newCall(Request.Builder().url(it).build()).execute().use { r ->
            r.body.bytes().let { b ->
                BitmapFactory.decodeByteArray(b, 0, b.size)
                    ?.let { bm -> bm.scale(300, 450) }
            }
        }
    }.onFailure { android.util.Log.w("AWWIDGET", "poster failed for $url: $it") }.getOrNull()
        .also { android.util.Log.i("AWWIDGET", "poster ${if (it == null) "none" else "${it.width}x${it.height}"} for $url") }
} }

private val CARD_BG = ColorProvider(Color(0xFF141414))
private val TITLE = TextStyle(color = ColorProvider(Color.White),
                              fontSize = 14.sp, fontWeight = FontWeight.Medium)
private val CAPTION = TextStyle(color = ColorProvider(Color(0xFFB0B0B0)), fontSize = 11.sp)

/**
 * Hands the launcher a generated preview of each widget (Android 15+), once per
 * app version: the picker otherwise shows an empty grid (seen on the Pixel).
 * The system rate-limits this call, so its answer is logged, not assumed.
 */
suspend fun publishWidgetPreviews(context: Context) {
    if (android.os.Build.VERSION.SDK_INT < 35) return
    val prefs = context.getSharedPreferences("aw_widgets", Context.MODE_PRIVATE)
    val version = app.archivewatch.android.BuildConfig.VERSION_CODE
    if (prefs.getInt("previews_for", -1) == version) return
    val mgr = androidx.glance.appwidget.GlanceAppWidgetManager(context)
    var ok = true
    for (r in listOf(ContinueWatchingWidgetReceiver::class, PickOfDayWidgetReceiver::class, SurpriseWidgetReceiver::class)) {
        val result = runCatching { mgr.setWidgetPreviews(r) }.getOrDefault(-1)
        android.util.Log.i("AWWIDGET", "preview ${r.simpleName} -> $result")
        if (result != androidx.glance.appwidget.GlanceAppWidgetManager.SET_WIDGET_PREVIEWS_RESULT_SUCCESS) ok = false
    }
    if (ok) prefs.edit { putInt("previews_for", version) }
}

// ---------------------------------------------------------------- Continue

class ContinueWatchingWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) = render(context)

    // The widget picker shows THIS (Android 15+): the widget itself, from the
    // same data, rather than the empty grid the picker drew before.
    override suspend fun providePreview(context: Context, widgetCategory: Int) = render(context)

    private suspend fun render(context: Context) {
        val container = (context.applicationContext as ArchiveWatchApplication).container
        val item: CatalogItem? = runCatching {
            val progress = container.userState.continueWatching().firstOrNull()
            progress?.let { container.catalog.awaitDb().item(it.archiveID) }
        }.getOrNull()
        val poster = fetchPoster(context, item?.posterURL)
        provideContent {
            Box(
                GlanceModifier.fillMaxSize().background(CARD_BG).cornerRadius(16.dp)
                    .clickable(actionStartActivity(deepLink(
                        context, "archivewatch://item/" + (item?.archiveID ?: "")))),
            ) {
                Column(GlanceModifier.fillMaxSize().padding(12.dp)) {
                    if (item == null) {
                        Text("Nothing in progress — open Archive Watch to start a film.",
                             style = CAPTION)
                    } else {
                        poster?.let {
                            Image(
                                provider = ImageProvider(it),
                                contentDescription = item.title,
                                contentScale = ContentScale.Crop,
                                modifier = GlanceModifier.fillMaxWidth()
                                    .defaultWeight().cornerRadius(10.dp),
                            )
                        }
                        Text(item.title, style = TITLE, maxLines = 1,
                             modifier = GlanceModifier.padding(top = 8.dp))
                        Text("Continue watching", style = CAPTION)
                    }
                }
            }
        }
    }
}

class ContinueWatchingWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ContinueWatchingWidget()
}

// ---------------------------------------------------------------- Pick of the Day

class PickOfDayWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) = render(context)

    // The widget picker shows THIS (Android 15+): the widget itself, from the
    // same data, rather than the empty grid the picker drew before.
    override suspend fun providePreview(context: Context, widgetCategory: Int) = render(context)

    private suspend fun render(context: Context) {
        val container = (context.applicationContext as ArchiveWatchApplication).container
        val item: CatalogItem? = runCatching {
            val db = container.catalog.awaitDb()
            // FULL rows: the lite ones carry no downloadURL, so this filter
            // emptied the pool and the widget said "Open Archive Watch to load
            // the catalog" every day (seen on the Pixel). recommendOnly: the
            // widget picks for the viewer, so Decision 149's flag applies.
            val pool = db.browse(limit = 200, homeOnly = true, full = true, recommendOnly = true)
                .filter { it.hasProfessionalArtwork && it.downloadURL != null }
            if (pool.isEmpty()) null else {
                // Date-seeded: the same pick all day, a new one tomorrow.
                val cal = Calendar.getInstance()
                val seed = cal.get(Calendar.YEAR) * 1000 + cal.get(Calendar.DAY_OF_YEAR)
                pool[java.util.Random(seed.toLong()).nextInt(pool.size)]
            }
        }.getOrNull()
        val poster = fetchPoster(context, item?.posterURL)
        provideContent {
            Box(
                GlanceModifier.fillMaxSize().background(CARD_BG).cornerRadius(16.dp)
                    .clickable(actionStartActivity(deepLink(
                        context, "archivewatch://item/" + (item?.archiveID ?: "")))),
            ) {
                Column(GlanceModifier.fillMaxSize().padding(12.dp)) {
                    if (item == null) {
                        Text("Open Archive Watch to load the catalog.", style = CAPTION)
                    } else {
                        poster?.let {
                            Image(
                                provider = ImageProvider(it),
                                contentDescription = item.title,
                                contentScale = ContentScale.Crop,
                                modifier = GlanceModifier.fillMaxWidth()
                                    .defaultWeight().cornerRadius(10.dp),
                            )
                        }
                        Text(item.title, style = TITLE, maxLines = 1,
                             modifier = GlanceModifier.padding(top = 8.dp))
                        Text("Pick of the day", style = CAPTION)
                    }
                }
            }
        }
    }
}

class PickOfDayWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = PickOfDayWidget()
}

// ---------------------------------------------------------------- Surprise

class SurpriseWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) = render(context)

    // The widget picker shows THIS (Android 15+): the widget itself, from the
    // same data, rather than the empty grid the picker drew before.
    override suspend fun providePreview(context: Context, widgetCategory: Int) = render(context)

    private suspend fun render(context: Context) {
        provideContent {
            Box(
                GlanceModifier.fillMaxSize().background(ColorProvider(Color(0xFFFF5C35)))
                    .cornerRadius(16.dp)
                    .clickable(actionStartActivity(deepLink(context, "archivewatch://surprise"))),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Surprise me",
                         style = TextStyle(color = ColorProvider(Color.Black),
                                           fontSize = 16.sp, fontWeight = FontWeight.Medium))
                    Text("a random film from the archive",
                         style = TextStyle(color = ColorProvider(Color(0xB3000000)),
                                           fontSize = 11.sp))
                }
            }
        }
    }
}

class SurpriseWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = SurpriseWidget()
}
