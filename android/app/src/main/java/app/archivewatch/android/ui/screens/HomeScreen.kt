package app.archivewatch.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.ShelfRow
import coil3.compose.AsyncImage
import kotlinx.coroutines.delay
import java.util.Calendar

private data class HomePayload(
    val hero: List<CatalogItem> = emptyList(),
    val continueWatching: List<CatalogItem> = emptyList(),
    val shelves: List<Pair<String, List<CatalogItem>>> = emptyList(),
    val topRated: List<CatalogItem> = emptyList(),
    val watchingNow: List<CatalogItem> = emptyList(),
    val communityFavorites: List<CatalogItem> = emptyList(),
    val mostDiscussed: List<CatalogItem> = emptyList(),
    val hiddenGems: List<CatalogItem> = emptyList(),
    val directorShelves: List<Pair<String, List<CatalogItem>>> = emptyList(),
    val publicDomainYear: Int = 0,
    val publicDomainDay: List<CatalogItem> = emptyList(),
    val categories: List<app.archivewatch.android.data.FeaturedCategory> = emptyList(),
    val decades: List<Pair<Int, Int>> = emptyList(),
    val loaded: Boolean = false,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val userChanges by container.userState.changes.collectAsState()

    val hideWatched by container.settings.hideWatchedOnHome.collectAsState(initial = false)

    val payload by produceState(HomePayload(), dbVersion, userChanges, hideWatched) {
        val db = container.catalog.db ?: return@produceState
        val featured = container.editorial.featured()
        // #17 parity: completed titles disappear from Home when the toggle is on.
        val watched = if (hideWatched) container.userState.completedIDs() else emptySet()

        // Featured shelves resolve by id through item_shelves (Decision 017);
        // curated shelves by explicit ids. Shelves under 6 tiles are stubs.
        val seen = mutableSetOf<String>()
        val shelves = mutableListOf<Pair<String, List<CatalogItem>>>()
        for (shelf in featured?.shelves.orEmpty()) {
            val resolved = if (shelf.type == "curated" && shelf.items.isNotEmpty()) {
                db.itemsByIDs(shelf.items.map { it.archiveID })
            } else {
                db.shelf(shelf.id, 32)
            }
            val deduped = resolved.filter { it.archiveID !in watched && seen.add(it.archiveID) }
            if (deduped.size >= 6) shelves.add(shelf.title.ifEmpty { shelf.id } to deduped.take(24))
        }

        // Hero pool: professional, wide-art-leaning titles from the shelves.
        val hero = shelves.flatMap { it.second }
            .filter { it.hasProfessionalArtwork }
            .distinctBy { it.archiveID }
            .sortedByDescending { it.backdropURL != null }
            .take(6)

        val cw = container.userState.continueWatching()
        val continueWatching = db.itemsByIDs(cw.map { it.archiveID })

        val pdYear = Calendar.getInstance().get(Calendar.YEAR) - 95
        // Category tiles count-gate >=30 (the apps' rule — a near-empty grid
        // never ships behind a tile).
        val categories = featured?.categories.orEmpty()
            .filter { db.browseCount(contentType = it.id) >= 30 }
        value = HomePayload(
            hero = hero,
            continueWatching = continueWatching,
            shelves = shelves,
            topRated = db.topRated().filter { it.archiveID !in watched },
            watchingNow = db.watchingNow().filter { it.archiveID !in watched && it.hasProfessionalArtwork },
            communityFavorites = db.communityFavorites().filter { it.archiveID !in watched && it.hasProfessionalArtwork },
            mostDiscussed = db.mostDiscussed().filter { it.archiveID !in watched && it.hasProfessionalArtwork },
            hiddenGems = db.hiddenGems(20).filter { it.archiveID !in watched },
            directorShelves = db.topDirectors().mapNotNull { d ->
                val films = db.byDirector(d).filter { it.archiveID !in watched }
                if (films.size >= 6) d to films else null
            },
            publicDomainYear = pdYear,
            publicDomainDay = db.browse(year = pdYear, limit = 24)
                .filter { it.archiveID !in watched },
            categories = categories,
            decades = db.decadeCounts(),
            loaded = true,
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Archive Watch", fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = { nav.push(Route.Surprise) }) {
                        Icon(Icons.Default.Shuffle, contentDescription = "Surprise me")
                    }
                    IconButton(onClick = { nav.push(Route.Settings) }) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        if (!payload.loaded) {
            LoadingBox(Modifier.padding(padding))
            return@Scaffold
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (payload.hero.isNotEmpty()) {
                item(key = "hero") { HeroCarousel(payload.hero) { nav.openItem(it.archiveID, it.seriesID, it.contentType) } }
            }
            if (payload.categories.isNotEmpty()) {
                item(key = "cats") {
                    CategoryTilesRow(payload.categories) { cat ->
                        nav.push(Route.Filtered(title = cat.displayName, contentType = cat.id))
                    }
                }
            }
            if (payload.continueWatching.isNotEmpty()) {
                item(key = "continue") {
                    ShelfRow("Continue Watching", payload.continueWatching, onItem = {
                        nav.openItem(it.archiveID, it.seriesID, it.contentType)
                    })
                }
            }
            payload.shelves.forEach { (title, items) ->
                item(key = "shelf-$title") {
                    ShelfRow(title, items, onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) })
                }
            }
            if (payload.topRated.isNotEmpty()) {
                item(key = "toprated") {
                    ShelfRow(
                        "Top Rated",
                        payload.topRated,
                        subtitle = "The crowd's verdict — IMDb favorites",
                        onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
                    )
                }
            }
            if (payload.watchingNow.isNotEmpty()) {
                item(key = "watchingnow") {
                    ShelfRow("Watching Now", payload.watchingNow,
                        subtitle = "Most-viewed on archive.org this month",
                        onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) })
                }
            }
            if (payload.communityFavorites.isNotEmpty()) {
                item(key = "commfav") {
                    ShelfRow("Community Favorites", payload.communityFavorites,
                        subtitle = "Most-favorited by archive.org viewers",
                        onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) })
                }
            }
            if (payload.mostDiscussed.isNotEmpty()) {
                item(key = "mostdisc") {
                    ShelfRow("Most Discussed", payload.mostDiscussed,
                        subtitle = "The films people are talking about",
                        onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) })
                }
            }
            if (payload.hiddenGems.isNotEmpty()) {
                item(key = "gems") {
                    ShelfRow(
                        "Hidden Gems",
                        payload.hiddenGems,
                        subtitle = "Lesser-known finds worth a look",
                        onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
                    )
                }
            }
            payload.directorShelves.forEach { (director, films) ->
                item(key = "dir-$director") {
                    ShelfRow("Directed by $director", films, onItem = {
                        nav.openItem(it.archiveID, it.seriesID, it.contentType)
                    })
                }
            }
            if (payload.publicDomainDay.isNotEmpty()) {
                item(key = "pdday") {
                    ShelfRow(
                        "Public Domain Day: ${payload.publicDomainYear}",
                        payload.publicDomainDay,
                        subtitle = "Newly free for everyone this year",
                        onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
                    )
                }
            }
            if (payload.decades.isNotEmpty()) {
                item(key = "eras") {
                    EraTilesRow(payload.decades) { decade ->
                        nav.push(Route.Filtered(title = "${decade}s", decade = decade))
                    }
                }
            }
            item(key = "footer") { Spacer(Modifier.height(24.dp)) }
        }
    }
}

/** Rotating hero — designed-art items, auto-advance every 7s. */
@Composable
private fun HeroCarousel(items: List<CatalogItem>, onItem: (CatalogItem) -> Unit) {
    val pagerState = rememberPagerState { items.size }
    LaunchedEffect(items.size) {
        while (true) {
            delay(7_000)
            val next = (pagerState.currentPage + 1) % items.size
            pagerState.animateScrollToPage(next)
        }
    }
    HorizontalPager(state = pagerState) { page ->
        val item = items[page]
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .aspectRatio(16f / 9f)
                .clip(RoundedCornerShape(16.dp))
                .clickable { onItem(item) },
        ) {
            AsyncImage(
                model = item.backdropURL ?: item.resolvedPosterURL,
                contentDescription = item.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            0.5f to Color.Transparent,
                            1f to Color.Black.copy(alpha = 0.85f),
                        ),
                    ),
            )
            Column(
                modifier = Modifier
                    .align(androidx.compose.ui.Alignment.BottomStart)
                    .padding(16.dp),
            ) {
                Text(
                    item.title,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 2,
                )
                val meta = listOfNotNull(item.year?.toString(), item.director).joinToString(" · ")
                if (meta.isNotEmpty()) {
                    Text(
                        meta,
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.8f),
                    )
                }
            }
        }
    }
}
