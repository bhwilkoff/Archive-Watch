package app.archivewatch.android.widgets

import android.content.Context
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
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.Calendar

/**
 * Home-screen widgets — the iOS WidgetKit suite's analogue (PARITY §8):
 * Continue Watching (your own resume state), Pick of the Day (the same
 * date-seeded editorial pick every device shows today), and Surprise Me
 * (one tap, one random film). Each deep-links into the app; nothing here
 * is a recommendation model's opinion (TV-DESIGN §1.4 spirit).
 */

private val http = OkHttpClient()

private fun deepLink(context: Context, uri: String): Intent =
    Intent(Intent.ACTION_VIEW, Uri.parse(uri)).setPackage(context.packageName)

private fun fetchPoster(url: String?): Bitmap? = url?.let {
    runCatching {
        http.newCall(Request.Builder().url(it).build()).execute().use { r ->
            r.body?.bytes()?.let { b ->
                BitmapFactory.decodeByteArray(b, 0, b.size)
                    ?.let { bm -> Bitmap.createScaledBitmap(bm, 300, 450, true) }
            }
        }
    }.getOrNull()
}

private val CARD_BG = ColorProvider(Color(0xFF141414))
private val TITLE = TextStyle(color = ColorProvider(Color.White),
                              fontSize = 14.sp, fontWeight = FontWeight.Medium)
private val CAPTION = TextStyle(color = ColorProvider(Color(0xFFB0B0B0)), fontSize = 11.sp)

// ---------------------------------------------------------------- Continue

class ContinueWatchingWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val container = (context.applicationContext as ArchiveWatchApplication).container
        val item: CatalogItem? = runCatching {
            val progress = container.userState.continueWatching().firstOrNull()
            progress?.let { container.catalog.awaitDb().item(it.archiveID) }
        }.getOrNull()
        val poster = fetchPoster(item?.posterURL)
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
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val container = (context.applicationContext as ArchiveWatchApplication).container
        val item: CatalogItem? = runCatching {
            val db = container.catalog.awaitDb()
            val pool = db.browse(limit = 200, homeOnly = true)
                .filter { it.hasProfessionalArtwork && it.downloadURL != null }
            if (pool.isEmpty()) null else {
                // Date-seeded: the same pick all day, a new one tomorrow.
                val cal = Calendar.getInstance()
                val seed = cal.get(Calendar.YEAR) * 1000 + cal.get(Calendar.DAY_OF_YEAR)
                pool[java.util.Random(seed.toLong()).nextInt(pool.size)]
            }
        }.getOrNull()
        val poster = fetchPoster(item?.posterURL)
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
    override suspend fun provideGlance(context: Context, id: GlanceId) {
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
