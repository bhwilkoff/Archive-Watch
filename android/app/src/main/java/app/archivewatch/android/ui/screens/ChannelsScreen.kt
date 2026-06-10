package app.archivewatch.android.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.ChannelPresets
import app.archivewatch.android.data.ChannelScheduler
import app.archivewatch.android.data.GuideChannel
import app.archivewatch.android.data.PlaySpec
import app.archivewatch.android.data.QueueEntry
import app.archivewatch.android.data.ScheduledProgram
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.theme.colorFromHex
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Channels (PARITY §5, ANDROID-DESIGN §4.6): the proportional EPG guide in the
// Material idiom. Same anatomy as tvOS/iOS: a sticky half-hour ruler, a fixed
// channel rail, program blocks sized to runtime on a shared time window —
// vertical scrolling only, with the window shifted by chevrons (±90 min,
// clamped to the broadcast day) and a NOW snap-back. Tap a block to tune in
// joined-in-progress: the lineup rides the existing Media3 queue with vintage
// commercials woven between programs; channel playback never persists resume
// progress (same rule as the Apple apps).

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun ChannelsScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    var windowStartMs by remember { mutableStateOf<Long?>(null) }   // null = live

    val guide by produceState<List<GuideChannel>?>(null, dbVersion) {
        val db = container.catalog.db ?: return@produceState
        val nowMs = System.currentTimeMillis()
        value = ChannelPresets.all.mapNotNull { preset ->
            val pool = db.browse(
                contentType = preset.contentType, genre = preset.genre,
                limit = 90,
            ).filter { it.downloadURL != null }
            val slots = ChannelScheduler.schedule(preset.id, pool, nowMs)
            if (slots.isEmpty()) null
            else GuideChannel(preset.id, preset.title, preset.accentHex, slots)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Channels", fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        val channels = guide
        if (channels == null) { LoadingBox(Modifier.padding(padding)); return@Scaffold }

        val nowMs = System.currentTimeMillis()
        val isCompact = LocalConfiguration.current.screenWidthDp < 600
        val windowMinutes = if (isCompact) 120 else 180
        val start = windowStartMs ?: nowMs
        val endMs = start + windowMinutes * 60_000L

        Column(Modifier.fillMaxSize().padding(padding)) {
            // Window controls: earlier / label / later / now.
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = {
                    windowStartMs = shift(windowStartMs, -90, nowMs)
                }) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Earlier")
                }
                Text(
                    "${timeLabel(start)} – ${timeLabel(endMs)}",
                    style = MaterialTheme.typography.labelLarge,
                    modifier = Modifier.weight(1f),
                    fontWeight = FontWeight.SemiBold,
                )
                IconButton(onClick = {
                    windowStartMs = shift(windowStartMs, 90, nowMs)
                }) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Later")
                }
                if (windowStartMs != null) {
                    Button(onClick = { windowStartMs = null }) { Text("Now") }
                }
            }

            val railW = 76.dp
            LazyColumn(Modifier.fillMaxSize()) {
                stickyHeader(key = "ruler") {
                    Ruler(startMs = start, windowMinutes = windowMinutes,
                          railW = railW, isLive = windowStartMs == null)
                }
                items(channels.size, key = { channels[it].id }) { idx ->
                    val ch = channels[idx]
                    ChannelGuideRow(
                        channel = ch, startMs = start, endMs = endMs,
                        windowMinutes = windowMinutes, railW = railW, nowMs = nowMs,
                        onTune = { slot -> tune(container, nav, ch, slot) },
                    )
                }
                item(key = "footer") { Spacer(Modifier.height(24.dp)) }
            }
        }
    }
}

private fun shift(current: Long?, minutes: Long, nowMs: Long): Long? {
    val proposed = (current ?: nowMs) + minutes * 60_000L
    val floor = ChannelScheduler.dayAnchorMs(nowMs)
    val ceiling = nowMs + 20 * 3600_000L
    val clamped = proposed.coerceIn(floor, ceiling)
    return if (kotlin.math.abs(clamped - nowMs) < 300_000L) null else clamped
}

private fun timeLabel(ms: Long): String =
    SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(ms))

private suspend fun tune(container: AppContainer, nav: Nav,
                         channel: GuideChannel, slot: ScheduledProgram) {
    val nowMs = System.currentTimeMillis()
    val lineup = ChannelScheduler.lineup(channel.slots, maxOf(slot.startMs, nowMs))
        .let { if (it.firstOrNull()?.item?.archiveID != slot.item.archiveID)
                   listOf(slot) + it else it }
    // Vintage commercials between programs (#89), same as the Apple apps.
    val ads = container.catalog.db
        ?.browse(contentType = "commercial", limit = 60)
        ?.filter { it.downloadURL != null }
        .orEmpty()
        .shuffled()
    val entries = ArrayList<QueueEntry>()
    lineup.forEachIndexed { i, sched ->
        val item = sched.item
        item.downloadURL?.let { url ->
            entries.add(QueueEntry(item.archiveID, item.title, channel.title, url))
        }
        if (ads.isNotEmpty() && i < lineup.size - 1) {
            val ad = ads[i % ads.size]
            ad.downloadURL?.let { url ->
                entries.add(QueueEntry(ad.archiveID, ad.title, "Commercial break", url))
            }
        }
    }
    if (entries.isEmpty()) return
    val joinOffset = if (slot.contains(nowMs)) maxOf(0L, nowMs - slot.startMs) else 0L
    nav.push(
        Route.Player(
            PlaySpec(
                id = entries.first().id,
                title = entries.first().title,
                subtitle = channel.title,
                url = entries.first().url,
                queue = entries,
                queueIndex = 0,
                startPositionMs = joinOffset,
                persistProgress = false,   // channels never persist resume
            ),
        ),
    )
}

@Composable
private fun Ruler(startMs: Long, windowMinutes: Int, railW: androidx.compose.ui.unit.Dp,
                  isLive: Boolean) {
    val ticks = windowMinutes / 30
    Row(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 8.dp),
    ) {
        Spacer(Modifier.width(railW + 4.dp))
        Row(Modifier.weight(1f)) {
            repeat(ticks) { i ->
                Text(
                    if (isLive && i == 0) "NOW" else timeLabel(startMs + i * 1800_000L),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = if (isLive && i == 0) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun ChannelGuideRow(channel: GuideChannel, startMs: Long, endMs: Long,
                            windowMinutes: Int, railW: androidx.compose.ui.unit.Dp,
                            nowMs: Long, onTune: suspend (ScheduledProgram) -> Unit) {
    val accent = colorFromHex(channel.accentHex) ?: MaterialTheme.colorScheme.primary
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        // Rail: accent chip + name.
        Column(
            Modifier.width(railW).height(64.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(
                Modifier.size(26.dp).clip(RoundedCornerShape(6.dp)).background(accent),
            )
            Text(
                channel.title,
                style = MaterialTheme.typography.labelSmall,
                maxLines = 2,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        // Timeline strip: proportional blocks placed by minute offset.
        androidx.compose.ui.layout.Layout(
            content = {
                val visible = channel.slots.filter { it.endMs > startMs && it.startMs < endMs }
                visible.forEach { slot ->
                    val airing = slot.contains(nowMs)
                    Column(
                        Modifier
                            .height(64.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .background(
                                if (airing) accent
                                else MaterialTheme.colorScheme.surfaceVariant,
                            )
                            .clickable { scope.launch { onTune(slot) } }
                            .padding(horizontal = 6.dp, vertical = 5.dp),
                    ) {
                        Text(
                            slot.item.title,
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = if (airing) FontWeight.Bold else FontWeight.SemiBold,
                            color = if (airing) Color.White
                                    else MaterialTheme.colorScheme.onSurface,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Spacer(Modifier.weight(1f))
                        Text(
                            timeLabel(slot.startMs),
                            style = MaterialTheme.typography.labelSmall,
                            color = if (airing) Color.White.copy(alpha = 0.85f)
                                    else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            },
            modifier = Modifier.weight(1f).height(64.dp).clipToBounds(),
        ) { measurables, constraints ->
            val totalW = constraints.maxWidth
            val pxPerMin = totalW.toFloat() / windowMinutes
            val visible = channel.slots.filter { it.endMs > startMs && it.startMs < endMs }
            val placeables = measurables.mapIndexed { i, m ->
                val slot = visible[i]
                val visStart = maxOf(slot.startMs, startMs)
                val visEnd = minOf(slot.endMs, endMs)
                val w = (((visEnd - visStart) / 60_000f) * pxPerMin - 4)
                    .toInt().coerceAtLeast(24)
                m.measure(
                    constraints.copy(minWidth = w, maxWidth = w,
                                     minHeight = constraints.maxHeight,
                                     maxHeight = constraints.maxHeight),
                )
            }
            layout(totalW, constraints.maxHeight) {
                placeables.forEachIndexed { i, p ->
                    val slot = visible[i]
                    val visStart = maxOf(slot.startMs, startMs)
                    val x = (((visStart - startMs) / 60_000f) * pxPerMin).toInt()
                    p.placeRelative(x, 0)
                }
            }
        }
    }
}
