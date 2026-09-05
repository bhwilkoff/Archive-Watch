package app.archivewatch.android.ui.tv

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.BuildConfig
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.BackdropImage
import app.archivewatch.android.ui.metaGenres
import app.archivewatch.android.ui.KindEyebrow
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.accentColor
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.screens.CategoryTilesRow
import app.archivewatch.android.ui.screens.EraTilesRow
import app.archivewatch.android.ui.screens.rememberHomePayload
import kotlinx.coroutines.delay

/**
 * TV Home (docs/TV-DESIGN.md §4.6 — rows at the root).
 *
 * Renders the SAME [rememberHomePayload] the phone Home renders, so the shelf
 * order and the cross-shelf dedup can never diverge between form factors. What
 * changes is the idiom: a full-bleed hero, ten-foot type, focus-scaled
 * shelves — and the Google TV signature: the focused card drives a dim
 * AMBIENT BACKDROP behind the whole surface (the ImmersiveList idiom), so
 * browsing feels like the room is lit by whatever you are considering.
 */
@Composable
fun TvHomeScreen(container: AppContainer, nav: Nav) {
    val payload by rememberHomePayload(container)
    val firstTile = remember { FocusRequester() }
    val anchor = remember { FocusRequester() }

    // Debug-only render trace. Screenshots proved unreliable here (a stale
    // frame from the previous run read as content), so the app says what it is
    // showing and the log is the evidence.
    if (BuildConfig.DEBUG) {
        androidx.compose.runtime.SideEffect {
            android.util.Log.i("AWHOME",
                if (payload.loaded) "content shelves=${payload.shelves.size} hero=${payload.hero != null}"
                else "LOADING")
        }
    }

    if (!payload.loaded) {
        // §3.1 — even a loading screen must hold focus, or the remote does
        // nothing until data lands and the user thinks the app has hung.
        FocusAnchor(anchor)
        ClaimInitialFocus(anchor)
        TvMessage("Loading the archive…")
        return
    }

    // The ambient backdrop follows FOCUS with a debounce: promoting every
    // focus stop while the viewer skims a row would strobe the whole screen.
    // 300ms means only a card the viewer RESTS on lights the room.
    var pendingAmbient by remember { mutableStateOf<CatalogItem?>(null) }
    var ambient by remember { mutableStateOf<CatalogItem?>(null) }
    LaunchedEffect(pendingAmbient) {
        val p = pendingAmbient ?: return@LaunchedEffect
        delay(300)
        ambient = p
    }
    val onItemFocused: (CatalogItem) -> Unit = { pendingAmbient = it }

    // Hero carousel: Right cycles forward, Left cycles back until the first
    // item, where Left falls through to the nav rail (the tvOS hero contract).
    var heroIndex by remember(payload.hero) { mutableIntStateOf(0) }
    val heroItem = payload.hero.getOrNull(heroIndex)
    val heroFocus = remember { FocusRequester() }

    // §3.1 — EXACTLY ONE surface claims initial focus, and it is the content,
    // not the nav rail (Left from here reaches the rail). Prefer the hero so
    // first paint shows it whole; fall back to the first shelf tile when no
    // hero qualifies. Two competing claims scrolled the hero off-screen —
    // caught on the Android TV emulator. Keyed on the hero POOL, not the
    // current index, or every Right press would re-claim and fight the cycle.
    ClaimInitialFocus(
        if (heroItem != null) heroFocus else firstTile,
        key = payload.hero.firstOrNull()?.archiveID ?: payload.shelves.firstOrNull()?.first,
    )

    Box(Modifier.fillMaxSize()) {
        // Ambient layer: LOW-ALPHA backdrop of the focused card, under
        // everything, crossfaded gently. Artwork may cross the overscan line
        // (§4.2); it carries no information — the shelves stay the content.
        Crossfade(
            targetState = ambient,
            animationSpec = tween(600),
            label = "ambient",
        ) { a ->
            if (a != null) {
                Box(Modifier.fillMaxSize()) {
                    BackdropImage(
                        url = a.backdropURL ?: a.posterURL,
                        contentDescription = null,
                        accent = a.accentColor,
                        modifier = Modifier.fillMaxSize().alpha(0.30f),
                    )
                    Box(
                        Modifier.fillMaxSize().background(
                            Brush.verticalGradient(
                                0f to Color(0x99000000),
                                0.5f to Color(0xCC000000),
                                1f to Color(0xF2000000),
                            ),
                        ),
                    )
                }
            }
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                bottom = TvDims.OverscanV * 2,
            ),
        ) {
            if (heroItem != null) {
                item(key = "hero") {
                    TvHero(
                        item = heroItem,
                        heroCount = payload.hero.size,
                        heroIndex = heroIndex,
                        focusRequester = heroFocus,
                        onPlay = { nav.openItem(heroItem.archiveID, heroItem.seriesID, heroItem.contentType) },
                        onCycle = { delta ->
                            heroIndex = (heroIndex + delta).mod(payload.hero.size)
                        },
                    )
                }
            }

            // Browse-by-Category tiles, in the phone/tvOS position (right after
            // the hero). The row was TV-branded in DiscoverScreens months ago
            // and then never rendered here, so the TV Home simply had no
            // category doors — measured on the Google TV 2026-09-03, the last
            // row was Public Domain Day and no tile row existed at all.
            if (payload.categories.isNotEmpty()) {
                item(key = "cats") {
                    CategoryTilesRow(payload.categories) { cat ->
                        nav.push(Route.Filtered(title = cat.displayName, contentType = cat.id))
                    }
                }
            }

            if (payload.continueWatching.isNotEmpty()) {
                item(key = "continue") {
                    TvShelfRow(
                        "Continue Watching",
                        payload.continueWatching,
                        onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
                        onItemFocused = onItemFocused,
                    )
                }
            }

            // The first editorial shelf owns the initial focus target.
            payload.shelves.forEachIndexed { index, (title, items) ->
                item(key = "shelf-$title") {
                    TvShelfRow(
                        title,
                        items,
                        onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
                        firstItemFocusRequester = if (index == 0) firstTile else null,
                        onItemFocused = onItemFocused,
                    )
                }
            }

            // §1.4 — these are OUR editorial + the community's own signals, each
            // with a subtitle saying where the ranking comes from. Never an opaque
            // "recommended for you" row.
            shelf("toprated", "Top Rated", "The crowd's verdict — IMDb favorites", payload.topRated, nav, onItemFocused)
            shelf("watchingnow", "Watching Now", "Most-viewed on archive.org this month", payload.watchingNow, nav, onItemFocused)
            shelf("commfav", "Community Favorites", "Most-favorited by archive.org viewers", payload.communityFavorites, nav, onItemFocused)
            shelf("discussed", "Most Discussed", "Most-reviewed on archive.org", payload.mostDiscussed, nav, onItemFocused)
            shelf("gems", "Hidden Gems", "Overlooked, and worth your time", payload.hiddenGems, nav, onItemFocused)

            payload.directorShelves.forEach { (director, films) ->
                shelf("dir-$director", director, "Films by this director", films, nav, onItemFocused)
            }

            if (payload.publicDomainDay.isNotEmpty()) {
                shelf(
                    "pdday",
                    "Public Domain Day ${payload.publicDomainYear}",
                    "Entered the public domain this year",
                    payload.publicDomainDay,
                    nav,
                    onItemFocused,
                )
            }

            // Era tiles are the LAST Home row on every platform (the apps' order).
            if (payload.decades.isNotEmpty()) {
                item(key = "eras") {
                    EraTilesRow(payload.decades) { decade ->
                        nav.push(Route.Filtered(title = "" + decade + "s", decade = decade))
                    }
                }
            }
        }
    }
}

/** Small helper so the shelf list above reads as a list of shelves. */
private fun androidx.compose.foundation.lazy.LazyListScope.shelf(
    key: String,
    title: String,
    subtitle: String?,
    items: List<CatalogItem>,
    nav: Nav,
    onItemFocused: (CatalogItem) -> Unit,
) {
    if (items.isEmpty()) return
    item(key = key) {
        TvShelfRow(
            title,
            items,
            subtitle = subtitle,
            onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
            onItemFocused = onItemFocused,
        )
    }
}

/**
 * Full-bleed hero. Artwork may cross the overscan line (§4.2) — text may not,
 * so the copy block sits inside the safe inset over a scrim that guarantees
 * contrast regardless of what the backdrop looks like.
 */
@Composable
private fun TvHero(
    item: CatalogItem,
    heroCount: Int,
    heroIndex: Int,
    focusRequester: FocusRequester,
    onPlay: () -> Unit,
    onCycle: (Int) -> Unit,
) {
    Box(
        Modifier
            .fillMaxWidth()
            // Sized so the whole hero — title included — fits above the first
            // shelf on a 1080p panel. It was 420dp, which pushed the title out
            // of frame once the first row scrolled into view.
            .height(360.dp),
    ) {
        Crossfade(targetState = item, animationSpec = tween(400), label = "hero") { h ->
            Box(Modifier.fillMaxSize()) {
                BackdropImage(
                    url = h.backdropURL,
                    contentDescription = h.title,
                    accent = h.accentColor,
                    modifier = Modifier.fillMaxSize(),
                )
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                0f to Color(0xCC000000),
                                0.45f to Color(0x33000000),
                                1f to Color(0xFF000000),
                            ),
                        ),
                )
                Column(
                    Modifier
                        .align(Alignment.BottomStart)
                        .padding(start = TvDims.OverscanH, bottom = 28.dp, end = TvDims.OverscanH)
                        .fillMaxWidth(0.55f),
                ) {
                    if (h.contentType.isNotBlank()) {
                        KindEyebrow(h.contentType, h.accentColor, Modifier.padding(bottom = 6.dp))
                    }
                    Text(
                        h.title,
                        fontSize = 36.sp,
                        lineHeight = 40.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    // The kind is the eyebrow; the meta line carries year + genres.
                    val meta = (listOfNotNull(h.year?.toString()) + metaGenres(h.genres))
                        .joinToString("  ·  ")
                    if (meta.isNotEmpty()) {
                        Text(
                            meta,
                            fontSize = 14.sp,
                            color = Color(0xFFCFCFCF),
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                    // §1.6 — one lean-in door on every surface: the hero says what the
                    // film IS, not just that it exists.
                    h.synopsis?.takeIf { it.isNotBlank() }?.let {
                        Text(
                            it,
                            fontSize = 15.sp,
                            lineHeight = 22.sp,
                            color = Color(0xFFE0E0E0),
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(top = 12.dp),
                        )
                    }
                }
            }
        }

        // Page dots — the only chrome the carousel adds; they say "there are
        // more of these" without stealing a focus stop (tvOS hero parity).
        if (heroCount > 1) {
            Row(
                Modifier
                    .align(Alignment.BottomEnd)
                    .padding(end = TvDims.OverscanH, bottom = 28.dp),
            ) {
                repeat(heroCount) { i ->
                    Box(
                        Modifier
                            .padding(horizontal = 4.dp)
                            .size(8.dp)
                            .background(
                                if (i == heroIndex) Color.White else Color(0x66FFFFFF),
                                CircleShape,
                            ),
                    )
                }
            }
        }

        // §1.6 — the hero is a door, not decoration: select opens the film,
        // which is also what makes it a legitimate initial focus target.
        //
        // The focus target is INSET by the overscan margin rather than laid on
        // the full-bleed box: §4.2 lets ARTWORK cross the overscan line but not
        // a resting focus ring, and a full-bleed ring sits exactly on the bezel
        // where a real panel would clip it.
        //
        // Right cycles the carousel; Left cycles back until index 0, where it
        // falls through to the nav rail — the same contract as the tvOS hero
        // (leftmost = sidebar). Handled on PREVIEW, on KEY DOWN: the focus
        // engine moves focus on the down event, so an up-handler let Left
        // reach the rail before the carousel ever saw it.
        Box(
            Modifier
                .fillMaxSize()
                .padding(horizontal = TvDims.OverscanH / 2, vertical = 10.dp)
                .onPreviewKeyEvent { ev ->
                    if (ev.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                    when (ev.key) {
                        Key.DirectionRight -> { onCycle(+1); true }
                        Key.DirectionLeft ->
                            if (heroIndex > 0) { onCycle(-1); true } else false
                        else -> false
                    }
                }
                .tvFocusable(
                    onClick = onPlay,
                    focusRequester = focusRequester,
                    shape = RoundedCornerShape(12.dp),
                    scaleWhenFocused = 1f,
                ),
        )
    }
}
