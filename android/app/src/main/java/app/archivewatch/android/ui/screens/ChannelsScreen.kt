package app.archivewatch.android.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Brush
import androidx.compose.material.icons.filled.Landscape
import androidx.compose.material.icons.filled.Mood
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.Nightlight
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material.icons.filled.Tv
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
import androidx.compose.ui.unit.sp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.ChannelPresets
import app.archivewatch.android.data.ChannelScheduler
import app.archivewatch.android.data.GuideChannel
import app.archivewatch.android.data.PlaySpec
import app.archivewatch.android.data.QueueEntry
import app.archivewatch.android.data.ScheduledProgram
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.tv.LocalIsTelevision
import androidx.compose.ui.focus.FocusRequester
import app.archivewatch.android.ui.tv.ClaimInitialFocus
import app.archivewatch.android.ui.tv.tvFocusable
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
    val userChanges by container.userState.changes.collectAsState()
    var windowStartMs by remember { mutableStateOf<Long?>(null) }   // null = live
    var showCreate by remember { mutableStateOf(false) }

    val guide by produceState<List<GuideChannel>?>(null, dbVersion, userChanges) {
        val db = container.catalog.awaitDb()
        val nowMs = System.currentTimeMillis()
        // User channels lead the guide (same as the Apple apps).
        val user = container.userState.userChannels().mapNotNull { uc ->
            val pool = db.browse(
                contentType = uc.contentType, genre = uc.genre,
                decade = uc.decade, limit = 150,
            ).filter { it.downloadURL != null }
            val slots = ChannelScheduler.schedule("user-${uc.id}", pool, nowMs)
            if (slots.isEmpty()) null
            else GuideChannel("user-${uc.id}", uc.name, "#0047FF", slots)
        }
        val presets = ChannelPresets.all.mapNotNull { preset ->
            val pool = db.browse(
                contentType = preset.contentType, genre = preset.genre,
                limit = 90,
            ).filter { it.downloadURL != null }
            val slots = ChannelScheduler.schedule(preset.id, pool, nowMs)
            if (slots.isEmpty()) null
            else GuideChannel(preset.id, preset.title, preset.accentHex, slots)
        }
        value = user + presets
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Channels", fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = { showCreate = true }) {
                        Icon(Icons.Default.Add, contentDescription = "Create channel")
                    }
                },
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

        if (showCreate) {
            CreateChannelDialog(container) { showCreate = false }
        }
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
                        // §3.3 — content, not chrome. Only the FIRST row claims,
                        // and only what is airing NOW: focusing the guide is the
                        // point, and "what's on right now" is what a viewer
                        // opening a TV guide is looking at.
                        claimInitialFocus = LocalIsTelevision.current && idx == 0,
                        onTune = { slot -> tune(container, nav, ch, slot) },
                        onDelete = if (ch.id.startsWith("user-")) ({
                            container.userState.deleteUserChannel(ch.id.removePrefix("user-"))
                        }) else null,
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
                            nowMs: Long, onTune: suspend (ScheduledProgram) -> Unit,
                            onDelete: (suspend () -> Unit)? = null,
                            claimInitialFocus: Boolean = false) {
    val accent = colorFromHex(channel.accentHex) ?: MaterialTheme.colorScheme.primary
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val isTv = LocalIsTelevision.current
    // Claimed by the airing block below, so the guide — not the header's "+"
    // button and not the nav rail — owns focus when Channels opens.
    val nowFocus = remember { FocusRequester() }
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        // Rail: accent chip + name; long-press a user channel's rail to delete.
        // Tap is a no-op (no full-day schedule screen yet) — suppress the ripple
        // so a plain tap doesn't read as a broken button.
        val railInteraction = remember { MutableInteractionSource() }
        Column(
            Modifier.width(railW).height(64.dp)
                .then(if (onDelete != null) {
                    Modifier.combinedClickable(
                        interactionSource = railInteraction,
                        indication = null,
                        onClick = {},
                        onLongClick = { scope.launch { onDelete() } },
                    )
                } else Modifier),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(
                Modifier.size(26.dp).clip(RoundedCornerShape(6.dp)).background(accent),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    channelIcon(channel.id), contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(17.dp),
                )
            }
            Text(
                channel.title,
                style = MaterialTheme.typography.labelSmall,
                maxLines = 2,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (claimInitialFocus) ClaimInitialFocus(nowFocus, key = channel.id)
        // Timeline strip: proportional blocks placed by minute offset.
        androidx.compose.ui.layout.Layout(
            content = {
                val visible = channel.slots.filter { it.endMs > startMs && it.startMs < endMs }
                // Initial-focus target for the guide — what a real EPG does:
                // focus what is ON NOW, unless it is nearly over, in which case
                // focus what is NEXT.
                //
                // Both halves were learned the hard way. "Always the airing
                // slot" put the ring on a 3-minute tail rendered ~24px wide — a
                // poor target. "The first slot that starts in view" then skipped
                // the airing programme entirely, because the window begins at
                // now, so the thing playing almost always started before it.
                val airingNow = visible.firstOrNull { it.contains(nowMs) }
                val focusSlot = airingNow?.takeIf { it.endMs - nowMs >= 5 * 60_000L }
                    ?: visible.firstOrNull { it.startMs >= nowMs }
                    ?: airingNow
                    ?: visible.firstOrNull()
                visible.forEach { slot ->
                    val airing = slot.contains(nowMs)
                    Column(
                        Modifier
                            .height(if (isTv) 84.dp else 64.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .background(
                                if (airing) accent
                                else MaterialTheme.colorScheme.surfaceVariant,
                            )
                            // `clickable` alone gives NO D-pad focus, so on a TV
                            // the entire guide was unreachable by remote — every
                            // press fell through to the nav rail (a TV-DP
                            // failure; verified on the emulator). The EPG layout
                            // itself is already a ten-foot idiom, so TV needs
                            // focusability, not a rewrite.
                            .then(
                                if (isTv) {
                                    val takesClaim = claimInitialFocus && slot === focusSlot
                                    Modifier.tvFocusable(
                                        onClick = { scope.launch { onTune(slot) } },
                                        focusRequester = if (takesClaim) nowFocus else null,
                                        shape = RoundedCornerShape(8.dp),
                                        ringColor = Color.White,
                                        scaleWhenFocused = 1f,
                                        focusTag = "program:" + slot.item.title.take(24),
                                    )
                                } else {
                                    Modifier.clickable { scope.launch { onTune(slot) } }
                                },
                            )
                            .padding(horizontal = if (isTv) 10.dp else 6.dp, vertical = 5.dp),
                    ) {
                        Text(
                            slot.item.title,
                            style = MaterialTheme.typography.labelMedium,
                            fontSize = if (isTv) 20.sp else androidx.compose.ui.unit.TextUnit.Unspecified,
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


/** Create a channel: genre / type / era filters (the Apple apps' form). */
@Composable
private fun CreateChannelDialog(container: AppContainer, onDone: () -> Unit) {
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var name by remember { mutableStateOf("") }
    var genre by remember { mutableStateOf<String?>(null) }
    var type by remember { mutableStateOf<String?>(null) }
    var decade by remember { mutableStateOf<Int?>(null) }
    val genres = listOf("Drama", "Comedy", "Crime", "Thriller", "Horror",
                        "Western", "Science Fiction", "Romance", "Mystery")
    val types = listOf("feature-film", "animation", "silent-film",
                       "short-film", "newsreel", "tv-special")
    val decades = (1900..2010 step 10).toList()
    val autoName = listOfNotNull(decade?.let { "${'$'}{it}s" }, genre,
        type?.replace('-', ' ')).joinToString(" ").ifEmpty { "My Channel" }

    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDone,
        title = { Text("Create a Channel") },
        confirmButton = {
            androidx.compose.material3.TextButton(
                onClick = {
                    scope.launch {
                        container.userState.createUserChannel(
                            name.trim().ifEmpty { autoName }, genre, type, decade)
                        onDone()
                    }
                },
                enabled = genre != null || type != null || decade != null,
            ) { Text("Create") }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDone) { Text("Cancel") }
        },
        text = {
            Column {
                PickRow("Genre", genres, genre) { genre = it }
                PickRow("Type", types.map { it.replace('-', ' ') }, type?.replace('-', ' ')) { sel ->
                    type = sel?.replace(' ', '-')
                }
                PickRow("Era", decades.map { "${'$'}{it}s" }, decade?.let { "${'$'}{it}s" }) { sel ->
                    decade = sel?.removeSuffix("s")?.toIntOrNull()
                }
                androidx.compose.material3.OutlinedTextField(
                    value = name, onValueChange = { name = it },
                    label = { Text(autoName) }, singleLine = true,
                )
            }
        },
    )
}

/** One-line horizontal chip picker (tap again to clear). */
@Composable
private fun PickRow(label: String, options: List<String>, selected: String?,
                    onPick: (String?) -> Unit) {
    Column(Modifier.padding(vertical = 4.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium,
             color = MaterialTheme.colorScheme.onSurfaceVariant)
        androidx.compose.foundation.lazy.LazyRow(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            items(options.size, key = { options[it] }) { i ->
                val opt = options[i]
                androidx.compose.material3.FilterChip(
                    selected = selected == opt,
                    onClick = { onPick(if (selected == opt) null else opt) },
                    label = { Text(opt) },
                )
            }
        }
    }
}


/** Per-channel rail glyph — the Material twin of the iOS preset SF Symbols
    (Models/Channels.swift); user-created channels get a star. */
private fun channelIcon(id: String): androidx.compose.ui.graphics.vector.ImageVector = when {
    id.startsWith("user-") -> Icons.Default.Star
    id == "drama" -> Icons.Default.TheaterComedy
    id == "comedy" -> Icons.Default.Mood
    id == "noir" -> Icons.Default.Search
    id == "thrill" -> Icons.Default.Bolt
    id == "horror" -> Icons.Default.Nightlight
    id == "western" -> Icons.Default.Landscape
    id == "scifi" -> Icons.Default.Science
    id == "silent" -> Icons.Default.Movie
    id == "cartoon" -> Icons.Default.Brush
    id == "news" -> Icons.Default.Newspaper
    id == "docs" -> Icons.Default.Public
    else -> Icons.Default.Tv   // tv / tv-comedy / tv-drama / tv-western
}
