package app.archivewatch.android.ui.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.OutlinedTextField
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.ui.layout.ContentScale
import coil3.compose.AsyncImage
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.focusable
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.data.PlaySpec
import app.archivewatch.android.ui.AvatarImage
import app.archivewatch.android.ui.BackdropImage
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.accentColor
import kotlinx.coroutines.launch

/**
 * TV Detail (docs/TV-DESIGN.md §2 — depth ≤ 2, so this is the last push).
 *
 * Reuses the phone screen's data path verbatim (`db.item` / `db.related` /
 * `userState`) and the same `PlaySpec` construction — only the presentation is
 * ten-foot. §1.6: the page is a door, not a poster, so the synopsis and the
 * "More Like This" row give the viewer somewhere to go next.
 */
@Composable
fun TvDetailScreen(container: AppContainer, nav: Nav, archiveID: String) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val scope = rememberCoroutineScope()

    var retry by remember { mutableIntStateOf(0) }
    val item by produceState<CatalogItem?>(null, archiveID, dbVersion, retry) {
        value = container.catalog.awaitDb().item(archiveID)
    }
    val related by produceState<List<CatalogItem>>(emptyList(), item) {
        value = item?.let { container.catalog.awaitDb().related(it) } ?: emptyList()
    }
    var showPlaylists by remember { mutableStateOf(false) }
    var showVersions by remember { mutableStateOf(false) }
    var showShare by remember { mutableStateOf(false) }
    var favorite by remember { mutableStateOf(false) }
    var watched by remember { mutableStateOf(false) }
    LaunchedEffect(archiveID) {
        favorite = container.userState.isFavorite(archiveID)
        watched = container.userState.isWatched(archiveID)
    }

    val playFocus = remember { FocusRequester() }
    val anchor = remember { FocusRequester() }

    val current = item
    if (current == null) {
        // Same 8s timeout as the phone screen: db.item() returns null BOTH while
        // the DB opens and for an id that isn't in the catalog, and without the
        // timeout the second case spins forever.
        val failed by produceState(false, archiveID, dbVersion, retry) {
            kotlinx.coroutines.delay(8_000)
            value = true
        }
        FocusAnchor(anchor)
        ClaimInitialFocus(anchor)
        TvMessage(
            if (failed) "This title isn't in the catalog anymore — it may have moved."
            else "Loading…",
        )
        return
    }

    // §3.1 — Play owns initial focus: it is what the viewer came for, and it
    // means one press of the remote starts the film. Suspended while the
    // playlist overlay is up, which claims its own.
    ClaimInitialFocus(playFocus, key = current.archiveID to showPlaylists,
        enabled = !showPlaylists)

    // Claiming focus on Play makes Compose bring PLAY into view, and it will
    // scroll the artwork off the top of the screen to do it — which is why a
    // title with a long description opened with the poster barely visible
    // (owner, 2026-08-28: "the poster should always be viewable upon looking
    // at the detail view initially"). Merging the hero and the actions into
    // one list item is not enough, because the scroll targets the focused
    // CHILD, not the item. So the list is pinned back to the top once focus
    // has settled: the viewer arrives looking at the artwork with Play
    // focused, and scrolling down to the description still works normally.
    val listState = rememberLazyListState()
    LaunchedEffect(current.archiveID) {
        kotlinx.coroutines.delay(300)
        runCatching { listState.scrollToItem(0) }
    }

    Box(Modifier.fillMaxSize()) {
    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = TvDims.OverscanV * 2),
    ) {
        // The artwork and the action row are ONE list item on purpose. As two,
        // claiming initial focus on Play made the list scroll Play into view
        // and pushed the 430dp hero off the top — so on a title with a long
        // description the poster was "almost unviewable" the moment the screen
        // opened (owner, 2026-08-28). Focus cannot bring one half of a single
        // item into view without the other, so the artwork is always on screen
        // when the viewer arrives; scrolling down to read still works.
        item(key = "hero") {
          Column {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(400.dp),
            ) {
                // This box is ~2.4:1. A landscape backdrop crops into it fine,
                // but a POSTER is 2:3 — cropping one here leaves a horizontal
                // sliver, which is what the owner saw on the Fire TV
                // (2026-08-31: "poorly proportioned and very often cropped
                // terribly (or not using the professional poster at all)").
                // Measured against the published catalog: 85.7% of titles have
                // no backdrop at all, and 12,431 of them carry a real designed
                // poster (tmdb/commons/omdb) that was being sliced.
                val heroBackdrop = current.backdropURL
                val heroPoster = current.posterURL
                // Ambient wash only. Cropping is correct for this layer because
                // it is texture behind a scrim, never something the viewer reads.
                BackdropImage(
                    url = heroBackdrop ?: heroPoster,
                    contentDescription = if (heroBackdrop != null) current.title else null,
                    accent = current.accentColor,
                    modifier = Modifier.fillMaxSize(),
                )
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                0f to Color(0x99000000),
                                0.5f to Color(0x66000000),
                                1f to Color(0xFF000000),
                            ),
                        ),
                )
                // With no backdrop, show the poster WHOLE at its own aspect,
                // trailing-aligned so it never collides with the title block
                // (which owns the leading 60%). Same resolution as iOS took on
                // 2026-06-11: aspect-FIT art over an ambient wash, never a
                // fill-cropped poster.
                if (heroBackdrop == null && heroPoster != null) {
                    AsyncImage(
                        model = heroPoster,
                        contentDescription = current.title,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .align(Alignment.CenterEnd)
                            .padding(end = TvDims.OverscanH, top = 20.dp, bottom = 20.dp)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(10.dp)),
                    )
                }
                Column(
                    Modifier
                        .align(Alignment.BottomStart)
                        .padding(start = TvDims.OverscanH, end = TvDims.OverscanH, bottom = 24.dp)
                        .fillMaxWidth(0.6f),
                ) {
                    Text(
                        current.title,
                        fontSize = 36.sp,
                        lineHeight = 40.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    // "Also known as" (Decision 100) — ten feet away the
                    // mismatch is starker: the title says one thing and the
                    // synopsis under it opens with another name for the film.
                    current.alsoKnownAs?.let { aka ->
                        Text(
                            "Also known as $aka",
                            fontSize = 18.sp,
                            fontStyle = FontStyle.Italic,
                            color = Color.White.copy(alpha = 0.75f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    val meta = listOfNotNull(
                        current.year?.toString(),
                        current.runtimeSeconds?.let { "${it / 60} min" },
                        current.contentType.replace('-', ' ').replaceFirstChar { it.uppercase() },
                        current.imdbRating?.takeIf { it > 0 }?.let { "★ " + it },
                    ).joinToString("  ·  ")
                    Text(
                        meta,
                        fontSize = 14.sp,
                        color = Color(0xFFCFCFCF),
                        modifier = Modifier.padding(top = 10.dp),
                    )
                }
            }

            Row(
                Modifier.padding(start = TvDims.OverscanH, top = 8.dp, bottom = 20.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val playable = current.downloadURL != null
                TvActionButton(
                    label = if (playable) "Play" else "Not playable",
                    icon = { Icon(Icons.Default.PlayArrow, null, tint = Color.Black, modifier = Modifier.size(20.dp)) },
                    focusRequester = playFocus,
                    primary = true,
                    enabled = playable,
                    accent = current.accentColor,
                ) {
                    current.downloadURL?.let { url ->
                        scope.launch {
                            // Episode binge: the season queue rides the spec
                            // (auto-advance + the MEDIA_NEXT/PREVIOUS keys).
                            val binge = if (current.isEpisode && current.seriesID != null) {
                                container.editorial.episodeBingeQueue(current.seriesID!!, current.archiveID)
                            } else null
                            nav.push(
                                Route.Player(
                                    PlaySpec(
                                        id = current.archiveID,
                                        title = current.title,
                                        description = current.synopsis,
                                        url = url,
                                        captions = current.captions ?: emptyList(),
                                        runtimeSeconds = current.runtimeSeconds,
                                        queue = binge?.first ?: emptyList(),
                                        queueIndex = binge?.second ?: 0,
                                    ),
                                ),
                            )
                        }
                    }
                }
                TvActionButton(
                    label = if (favorite) "Favorited" else "Favorite",
                    icon = {
                        Icon(
                            if (favorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                            null, tint = Color.White, modifier = Modifier.size(18.dp),
                        )
                    },
                    accent = current.accentColor,
                ) {
                    scope.launch { favorite = container.userState.toggleFavorite(current.archiveID) }
                }
                TvActionButton(
                    label = if (watched) "Watched" else "Mark Watched",
                    icon = {
                        Icon(
                            Icons.Default.Visibility, null,
                            tint = if (watched) current.accentColor else Color.White,
                            modifier = Modifier.size(18.dp),
                        )
                    },
                    accent = current.accentColor,
                ) {
                    scope.launch {
                        container.userState.setWatched(current.archiveID, !watched)
                        watched = !watched
                    }
                }
                TvActionButton(
                    label = "Add to Playlist",
                    icon = { Icon(Icons.AutoMirrored.Filled.PlaylistAdd, null, tint = Color.White, modifier = Modifier.size(18.dp)) },
                    accent = current.accentColor,
                ) { showPlaylists = true }
                TvActionButton(
                    label = "Share",
                    icon = { Icon(Icons.Default.Share, null, tint = Color.White, modifier = Modifier.size(18.dp)) },
                    accent = current.accentColor,
                ) { showShare = true }
                TvActionButton(
                    label = "Version",
                    icon = { Icon(Icons.Default.Tune, null, tint = Color.White, modifier = Modifier.size(18.dp)) },
                    accent = current.accentColor,
                ) { showVersions = true }
                // Decision 045 — an episode is a door back to its series.
                if (current.isEpisode && current.seriesID != null) {
                    TvActionButton(
                        label = "Part of " + (current.seriesTitle ?: "the series"),
                        icon = { Icon(Icons.Default.Tv, null, tint = Color.White, modifier = Modifier.size(18.dp)) },
                        accent = current.accentColor,
                    ) { nav.push(Route.Series(current.seriesID!!)) }
                }
            }
          }
        }

        current.synopsis?.takeIf { it.isNotBlank() }?.let { synopsis ->
            item(key = "synopsis") {
                // FOCUSABLE, so the D-pad can stop on it and the LazyColumn
                // will scroll it into view. A TV list only scrolls to things
                // focus can reach, so a long synopsis between Play and the
                // cast row is skipped entirely and its tail is unreadable
                // (owner, 2026-08-28: everything on the TV should be viewable,
                // even without a toggle to flip). Focusing it also brightens
                // it, so the viewer can see where they are.
                var focused by remember { mutableStateOf(false) }
                Text(
                    synopsis,
                    fontSize = 15.sp,
                    lineHeight = 23.sp,
                    color = if (focused) Color.White else Color(0xFFDDDDDD),
                    modifier = Modifier
                        .padding(start = TvDims.OverscanH, end = TvDims.OverscanH, bottom = 24.dp)
                        .fillMaxWidth(0.72f)
                        .onFocusChanged { focused = it.isFocused }
                        .focusable(),
                )
            }
        }

        // Cast → person filmography (tvOS Detail parity): director leads with a
        // role caption, then the billed cast, each chip a door to byPerson.
        val people = buildList {
            current.director?.takeIf { it.isNotBlank() }?.let {
                add(TvPerson(it, "Director", null, current.directorProfilePath?.let { p ->
                    if (p.startsWith("http")) p else "https://image.tmdb.org/t/p/w185" + p
                }))
            }
            current.cast.take(12).forEach {
                add(TvPerson(it.name, it.character ?: "Cast", it.tmdbPersonID, it.profileURL))
            }
        }
        if (people.isNotEmpty()) {
            item(key = "people") {
                Column(Modifier.padding(bottom = 24.dp)) {
                    TvSectionTitle("Cast & Crew", Modifier.padding(start = TvDims.OverscanH, bottom = 12.dp))
                    LazyRow(
                        contentPadding = PaddingValues(start = TvDims.OverscanH, end = TvDims.OverscanH * 2),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        items(people.size, key = { people[it].name + it }) { i ->
                            val person = people[i]
                            Row(
                                Modifier
                                    .tvFocusable(
                                        onClick = { nav.push(Route.Person(person.name, person.pid)) },
                                        shape = RoundedCornerShape(24.dp),
                                        scaleWhenFocused = 1.04f,
                                    )
                                    .background(Color(0xFF1C1C1C), RoundedCornerShape(24.dp))
                                    .padding(start = 6.dp, end = 16.dp, top = 6.dp, bottom = 6.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                AvatarImage(
                                    url = person.photo,
                                    name = person.name,
                                    modifier = Modifier.size(40.dp).clip(CircleShape),
                                )
                                Column(Modifier.padding(start = 10.dp)) {
                                    Text(person.name, fontSize = 14.sp, color = Color.White, fontWeight = FontWeight.Medium)
                                    Text(person.role, fontSize = 12.sp, color = Color(0xFF9A9A9A))
                                }
                            }
                        }
                    }
                }
            }
        }

        // archive.org community stats + genuine reviews (pipeline-filtered,
        // comment_fit.py) — the tvOS CommunityDetailSection, ten-foot.
        val communityReviews = current.displayReviews
        val hasStats = current.viewsDisplay != null || current.favoritesDisplay != null ||
            current.avgRatingDisplay != null
        if (hasStats || communityReviews.isNotEmpty()) {
            item(key = "community") {
                Column(Modifier.padding(start = TvDims.OverscanH, end = TvDims.OverscanH, bottom = 24.dp)) {
                    if (hasStats) {
                        Row(horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                            current.viewsDisplay?.let { TvStat(it, "views") }
                            current.favoritesDisplay?.let { TvStat(it, "favorites") }
                            current.avgRatingDisplay?.let { TvStat("★ " + it, "viewer rating") }
                        }
                    }
                    if (communityReviews.isNotEmpty()) {
                        TvSectionTitle("From archive.org viewers", Modifier.padding(top = 20.dp, bottom = 12.dp))
                        LazyRow(
                            contentPadding = PaddingValues(end = TvDims.OverscanH),
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                        ) {
                            items(communityReviews.take(6).size, key = { "rev" + it }) { i ->
                                val r = communityReviews[i]
                                Column(
                                    Modifier
                                        .width(360.dp)
                                        .tvFocusable(onClick = {}, shape = RoundedCornerShape(12.dp), scaleWhenFocused = 1.02f)
                                        .background(Color(0xFF161616), RoundedCornerShape(12.dp))
                                        .padding(16.dp),
                                ) {
                                    r.stars?.takeIf { it > 0 }?.let { s ->
                                        Text("★".repeat(s.toInt()), fontSize = 13.sp, color = Color(0xFFE8A317))
                                    }
                                    r.title?.takeIf { it.isNotBlank() }?.let {
                                        Text(it, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Color.White,
                                            maxLines = 1, overflow = TextOverflow.Ellipsis,
                                            modifier = Modifier.padding(top = 4.dp))
                                    }
                                    r.body?.takeIf { it.isNotBlank() }?.let {
                                        Text(it, fontSize = 13.sp, lineHeight = 19.sp, color = Color(0xFFB9B9B9),
                                            maxLines = 5, overflow = TextOverflow.Ellipsis,
                                            modifier = Modifier.padding(top = 6.dp))
                                    }
                                    Text(
                                        r.displayName + (r.date?.let { " · " + it } ?: ""),
                                        fontSize = 11.sp, color = Color(0xFF808080),
                                        modifier = Modifier.padding(top = 8.dp),
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        if (related.isNotEmpty()) {
            item(key = "related") {
                TvShelfRow(
                    "More Like This",
                    related,
                    onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
                )
            }
        }
    }

    if (showShare) {
        TvShareOverlay(
            title = current.title,
            url = if (current.contentType == "tv-series")
                "https://archivewatch.org/series/" + current.archiveID.removePrefix("series:")
            else "https://archivewatch.org/item/" + current.archiveID,
            onDone = { showShare = false },
        )
    }
    if (showVersions) {
        TvVersionOverlay(
            archiveID = current.archiveID,
            accent = current.accentColor,
            onDone = { showVersions = false },
        )
    }
    if (showPlaylists) {
        TvPlaylistOverlay(
            container = container,
            archiveID = current.archiveID,
            accent = current.accentColor,
            onDone = { showPlaylists = false },
        )
    }
    }
}

/**
 * TV-native Add to Playlist: a right-side focusable panel (a phone dialog's
 * touch targets are unusable at ten feet). Rows toggle membership; the last
 * row creates a playlist from the typed name (the leanback IME opens on the
 * field). Back or Done dismisses.
 */
@Composable
private fun TvPlaylistOverlay(
    container: AppContainer,
    archiveID: String,
    accent: Color,
    onDone: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var version by remember { mutableIntStateOf(0) }
    val playlists by produceState<List<app.archivewatch.android.data.UserPlaylist>>(emptyList(), version) {
        value = container.userState.playlists()
    }
    var newName by remember { mutableStateOf("") }
    val firstFocus = remember { FocusRequester() }
    val doneFocus = remember { FocusRequester() }
    // §3.1 — the overlay must own focus even when the list is EMPTY, or the
    // D-pad keeps driving the dimmed detail behind the scrim (measured on
    // device: zero playlists left the Add button focused under the overlay).
    ClaimInitialFocus(
        if (playlists.isEmpty()) doneFocus else firstFocus,
        key = playlists.isEmpty(),
    )
    // Back closes the overlay, never the route behind it.
    androidx.activity.compose.BackHandler(true) { onDone() }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color(0xCC000000)),
    ) {
        Column(
            Modifier
                .align(Alignment.CenterEnd)
                .fillMaxHeight()
                .fillMaxWidth(0.42f)
                .background(Color(0xFF141414))
                .padding(horizontal = 36.dp, vertical = TvDims.OverscanV),
        ) {
            Text("Add to Playlist", fontSize = 22.sp, fontWeight = FontWeight.Medium, color = Color.White,
                modifier = Modifier.padding(bottom = 20.dp))
            LazyColumn(Modifier.weight(1f)) {
                itemsIndexed(playlists, key = { _, pl -> pl.id }) { index, pl ->
                    val contains = archiveID in pl.archiveIDs
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(vertical = 6.dp)
                            .tvFocusable(
                                onClick = {
                                    scope.launch {
                                        container.userState.togglePlaylistItem(pl.id, archiveID)
                                        version += 1
                                    }
                                },
                                focusRequester = if (index == 0) firstFocus else null,
                                shape = RoundedCornerShape(12.dp),
                                scaleWhenFocused = 1.02f,
                            )
                            .background(Color(0xFF1F1F1F), RoundedCornerShape(12.dp))
                            .padding(horizontal = 20.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(pl.name, fontSize = 15.sp, color = Color.White, modifier = Modifier.weight(1f))
                        Icon(
                            if (contains) Icons.Default.Check else Icons.AutoMirrored.Filled.PlaylistAdd,
                            null,
                            tint = if (contains) accent else Color(0xFF777777),
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }
            OutlinedTextField(
                value = newName,
                onValueChange = { newName = it },
                placeholder = { Text("New playlist name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
            )
            Row(
                Modifier.padding(top = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                TvActionButton(
                    label = "Create",
                    icon = { Icon(Icons.AutoMirrored.Filled.PlaylistAdd, null, tint = Color.Black, modifier = Modifier.size(18.dp)) },
                    primary = true,
                    enabled = newName.isNotBlank(),
                    accent = accent,
                ) {
                    scope.launch {
                        container.userState.createPlaylist(newName.trim(), archiveID)
                        newName = ""
                        version += 1
                    }
                }
                TvActionButton(
                    label = "Done",
                    icon = { Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(18.dp)) },
                    accent = accent,
                    focusRequester = doneFocus,
                ) { onDone() }
            }
        }
    }
}

/**
 * A ten-foot action button. Deliberately NOT Material3 `Button`: the phone
 * button is sized for a fingertip and its ripple/elevation carry pressed state,
 * neither of which reads at ten feet. Here focus is the state that matters
 * (§3.2 — scale + ring + lift), so the button is a focusable surface.
 */
@Composable
private fun TvActionButton(
    label: String,
    icon: @Composable () -> Unit,
    accent: Color,
    focusRequester: FocusRequester? = null,
    primary: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .tvFocusable(
                onClick = { if (enabled) onClick() },
                focusRequester = focusRequester,
                shape = RoundedCornerShape(28.dp),
                ringColor = Color.White,
                scaleWhenFocused = 1.05f,
            )
            .background(
                when {
                    !enabled -> Color(0xFF2A2A2A)
                    primary -> accent
                    else -> Color(0xFF1C1C1C)
                },
                RoundedCornerShape(28.dp),
            )
            .padding(horizontal = 20.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon()
        Text(
            label,
            fontSize = 15.sp,
            fontWeight = if (primary) FontWeight.Medium else FontWeight.Normal,
            color = when {
                !enabled -> Color(0xFF888888)
                primary -> Color.Black
                else -> Color.White
            },
        )
    }
}

private data class TvPerson(val name: String, val role: String, val pid: Int?, val photo: String?)

@Composable
private fun TvStat(value: String, caption: String) {
    Column {
        Text(value, fontSize = 18.sp, fontWeight = FontWeight.Medium, color = Color.White)
        Text(caption, fontSize = 12.sp, color = Color(0xFF9A9A9A))
    }
}

/**
 * Every playable copy on the archive.org item, viewer-choosable (the tvOS
 * VersionPicker, ten-foot). Fetched when opened; the choice persists
 * per-title and the player honours it via ArchiveVersions.preferredURL.
 */
@Composable
private fun TvVersionOverlay(
    archiveID: String,
    accent: Color,
    onDone: () -> Unit,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var versions by remember { mutableStateOf<List<app.archivewatch.android.data.ArchiveVersions.Version>?>(null) }
    var chosen by remember {
        mutableStateOf(app.archivewatch.android.data.ArchiveVersions.chosenName(context, archiveID))
    }
    LaunchedEffect(archiveID) {
        versions = app.archivewatch.android.data.ArchiveVersions.list(archiveID)
    }
    val firstFocus = remember { FocusRequester() }
    ClaimInitialFocus(firstFocus, key = versions != null)
    androidx.activity.compose.BackHandler(true) { onDone() }

    Box(Modifier.fillMaxSize().background(Color(0xCC000000))) {
        Column(
            Modifier
                .align(Alignment.CenterEnd)
                .fillMaxHeight()
                .fillMaxWidth(0.46f)
                .background(Color(0xFF141414))
                .padding(horizontal = 36.dp, vertical = TvDims.OverscanV),
        ) {
            Text("Choose a Copy", fontSize = 22.sp, fontWeight = FontWeight.Medium, color = Color.White)
            Text(
                "The Archive often holds several transfers of the same film.",
                fontSize = 13.sp, color = Color(0xFF9A9A9A),
                modifier = Modifier.padding(top = 4.dp, bottom = 16.dp),
            )
            when (val v = versions) {
                null -> Text("Loading copies…", fontSize = 14.sp, color = Color(0xFF9A9A9A))
                else -> LazyColumn(Modifier.weight(1f)) {
                    item(key = "default") {
                        TvVersionRow(
                            label = "Pipeline pick (default)",
                            selected = chosen == null,
                            accent = accent,
                            focusRequester = firstFocus,
                        ) {
                            app.archivewatch.android.data.ArchiveVersions.choose(context, archiveID, null)
                            chosen = null
                        }
                    }
                    items(v.size, key = { v[it].name }) { i ->
                        val ver = v[i]
                        TvVersionRow(
                            label = ver.label,
                            selected = chosen == ver.name,
                            accent = accent,
                        ) {
                            app.archivewatch.android.data.ArchiveVersions.choose(context, archiveID, ver)
                            chosen = ver.name
                        }
                    }
                    if (v.isEmpty()) {
                        item(key = "none") {
                            Text("Couldn't load this item's file list.", fontSize = 14.sp, color = Color(0xFF9A9A9A))
                        }
                    }
                }
            }
            TvActionButton(
                label = "Done",
                icon = { Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(18.dp)) },
                accent = accent,
            ) { onDone() }
        }
    }
}

@Composable
private fun TvVersionRow(
    label: String,
    selected: Boolean,
    accent: Color,
    focusRequester: FocusRequester? = null,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 5.dp)
            .tvFocusable(
                onClick = onClick,
                focusRequester = focusRequester,
                shape = RoundedCornerShape(12.dp),
                scaleWhenFocused = 1.02f,
            )
            .background(Color(0xFF1F1F1F), RoundedCornerShape(12.dp))
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, fontSize = 14.sp, color = Color.White, modifier = Modifier.weight(1f))
        if (selected) {
            Icon(Icons.Default.Check, null, tint = accent, modifier = Modifier.size(20.dp))
        }
    }
}