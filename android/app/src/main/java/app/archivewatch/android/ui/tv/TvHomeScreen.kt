package app.archivewatch.android.ui.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.BackdropImage
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.accentColor
import app.archivewatch.android.ui.screens.rememberHomePayload

/**
 * TV Home (docs/TV-DESIGN.md §4.6 — rows at the root).
 *
 * Renders the SAME [rememberHomePayload] the phone Home renders, so the shelf
 * order and the cross-shelf dedup can never diverge between form factors. What
 * changes is the idiom: a full-bleed hero, ten-foot type, and focus-scaled
 * shelves instead of a scrolling touch list.
 */
@Composable
fun TvHomeScreen(container: AppContainer, nav: Nav) {
    val payload by rememberHomePayload(container)
    val firstTile = remember { FocusRequester() }
    val anchor = remember { FocusRequester() }

    if (!payload.loaded) {
        // §3.1 — even a loading screen must hold focus, or the remote does
        // nothing until data lands and the user thinks the app has hung.
        FocusAnchor(anchor)
        ClaimInitialFocus(anchor)
        TvMessage("Loading the archive…")
        return
    }

    // §3.1 — claim focus on the first real tile once content exists.
    ClaimInitialFocus(firstTile, key = payload.shelves.firstOrNull()?.first)

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            bottom = TvDims.OverscanV * 2,
        ),
    ) {
        if (payload.hero.isNotEmpty()) {
            item(key = "hero") { TvHero(payload.hero.first()) }
        }

        if (payload.continueWatching.isNotEmpty()) {
            item(key = "continue") {
                TvShelfRow(
                    "Continue Watching",
                    payload.continueWatching,
                    onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
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
                )
            }
        }

        // §1.4 — these are OUR editorial + the community's own signals, each
        // with a subtitle saying where the ranking comes from. Never an opaque
        // "recommended for you" row.
        shelf("toprated", "Top Rated", "The crowd's verdict — IMDb favorites", payload.topRated, nav)
        shelf("watchingnow", "Watching Now", "Most-viewed on archive.org this month", payload.watchingNow, nav)
        shelf("commfav", "Community Favorites", "Most-favorited by archive.org viewers", payload.communityFavorites, nav)
        shelf("discussed", "Most Discussed", "Most-reviewed on archive.org", payload.mostDiscussed, nav)
        shelf("gems", "Hidden Gems", "Overlooked, and worth your time", payload.hiddenGems, nav)

        payload.directorShelves.forEach { (director, films) ->
            shelf("dir-$director", director, "Films by this director", films, nav)
        }

        if (payload.publicDomainDay.isNotEmpty()) {
            shelf(
                "pdday",
                "Public Domain Day ${payload.publicDomainYear}",
                "Entered the public domain this year",
                payload.publicDomainDay,
                nav,
            )
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
) {
    if (items.isEmpty()) return
    item(key = key) {
        TvShelfRow(
            title,
            items,
            subtitle = subtitle,
            onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
        )
    }
}

/**
 * Full-bleed hero. Artwork may cross the overscan line (§4.2) — text may not,
 * so the copy block sits inside the safe inset over a scrim that guarantees
 * contrast regardless of what the backdrop looks like.
 */
@Composable
private fun TvHero(item: CatalogItem) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(420.dp),
    ) {
        BackdropImage(
            url = item.backdropURL,
            contentDescription = item.title,
            accent = item.accentColor,
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
            Text(
                item.title,
                fontSize = 56.sp,
                lineHeight = 60.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            val meta = listOfNotNull(
                item.year?.toString(),
                item.contentType.replace('-', ' ').replaceFirstChar { it.uppercase() }
                    .takeIf { item.contentType.isNotBlank() },
            ).joinToString("  ·  ")
            if (meta.isNotEmpty()) {
                Text(
                    meta,
                    fontSize = 22.sp,
                    color = Color(0xFFCFCFCF),
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            // §1.6 — one lean-in door on every surface: the hero says what the
            // film IS, not just that it exists.
            item.synopsis?.takeIf { it.isNotBlank() }?.let {
                Text(
                    it,
                    fontSize = 22.sp,
                    lineHeight = 30.sp,
                    color = Color(0xFFE0E0E0),
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 12.dp),
                )
            }
        }
    }
}
