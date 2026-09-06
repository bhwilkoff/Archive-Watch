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
import androidx.compose.runtime.remember
import androidx.compose.runtime.produceState
import androidx.compose.runtime.State
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.archivewatch.android.BuildConfig
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.BrowseSort
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.BackdropImage
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.accentColor
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.ShelfRow
import coil3.compose.AsyncImage
import kotlinx.coroutines.delay
import java.util.Calendar
import kotlin.random.Random

internal data class HomePayload(
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

// The canonical Home shelf order, matching Apple TV (Featured.homeShelfPriority on Apple) — owner
// 2026-06-29: replicated across all platforms.
private val HOME_SHELF_PRIORITY = listOf(
    "popular-features", "wikidata-pd", "film-noir", "scifi-horror",
    "silent-hall-of-fame", "melies", "video-cellar", "comedy",
    "animation-all", "vintage-cartoons", "nasa", "classic-tv-1960s",
    "classic-tv-1950s", "classic-tv-1970s", "ephemera", "newsreels",
    "educational", "picfixer", "silent-era", "popular-classic-tv",
    "all-time-features",
)

/**
 * The Home data assembly, shared by the phone Home and the TV Home
 * (docs/TV-DESIGN.md §1.1 — one product, two idioms).
 *
 * It lives here, once, because the cross-shelf dedup (`seen`) is subtle and
 * load-bearing: no title may repeat across ANY Home shelf on any platform, and
 * a second copy of this logic would drift. TV renders the same payload with TV
 * components; it does not re-derive it.
 */
@Composable
internal fun rememberHomePayload(container: AppContainer): State<HomePayload> {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val userChanges by container.userState.changes.collectAsState()
    val hideWatched by container.settings.hideWatchedOnHome.collectAsState(initial = false)

    // The last COMPLETED payload survives a re-query. When the full catalog
    // swapped in over the seed, the producer was cancelled and Home fell back
    // to "Loading the archive…" — throwing away a rendered screen and making
    // the app look like it had restarted. Holding the previous payload means
    // the seed's Home stays up and is replaced in place when the richer answer
    // arrives.
    val held = remember { mutableStateOf(HomePayload()) }

    return produceState(held.value, dbVersion, userChanges, hideWatched) {
        val qt0 = android.os.SystemClock.elapsedRealtime()
        fun qmark(what: String) {
            if (BuildConfig.DEBUG) android.util.Log.i(
                "AWQ", "$what +${android.os.SystemClock.elapsedRealtime() - qt0}ms")
        }
        qmark("producer:start")
        val db = container.catalog.awaitDb()
        qmark("awaitDb")
        val featured = container.editorial.featured()
        // #17 parity: completed titles disappear from Home when the toggle is on.
        val watched = if (hideWatched) container.userState.completedIDs() else emptySet()

        // Featured shelves resolve by id through item_shelves (Decision 017);
        // curated shelves by explicit ids. Shelves under 6 tiles are stubs.
        // ONE shared seen-set across EVERY Home shelf so no title repeats anywhere
        // (keyed on dedupKey, not archiveID — also collapses re-uploads of the same
        // film). Claimed in render order: Continue Watching first (it renders above
        // the shelves), then the featured shelves, then the dynamic/community shelves,
        // then directors and Public Domain Day. A shelf that overlaps an earlier one
        // shrinks below its floor and HIDES instead of repeating (apps' parity).
        val seen = mutableSetOf<String>()

        // Claim up to `limit` fresh items from a pool (skipping watched + already-seen,
        // deduping within the pool too); keep the shelf only if it clears `min`.
        fun claim(pool: List<CatalogItem>, limit: Int = 24, min: Int = 6): List<CatalogItem> {
            val taken = ArrayList<CatalogItem>()
            val local = HashSet<String>()
            for (it in pool) {
                if (it.archiveID in watched) continue
                val k = it.dedupKey
                if (k in seen || k in local) continue
                local.add(k); taken.add(it)
                if (taken.size >= limit) break
            }
            if (taken.size < min) return emptyList()
            seen.addAll(local)
            return taken
        }

        // Continue Watching claims first so its titles never resurface below.
        val cw = container.userState.continueWatching()
        val continueWatching = db.itemsByIDs(cw.map { it.archiveID })
        continueWatching.forEach { seen.add(it.dedupKey) }

        // Featured shelves in the CANONICAL Apple-TV order (not featured.json file order) — owner
        // 2026-06-29 shelf parity. Ids absent from the catalog are skipped.
        val byId = featured?.shelves.orEmpty().associateBy { it.id }
        val shelves = mutableListOf<Pair<String, List<CatalogItem>>>()
        for (id in HOME_SHELF_PRIORITY) {
            val shelf = byId[id] ?: continue
            val resolved = if (shelf.type == "curated" && shelf.items.isNotEmpty()) {
                db.itemsByIDs(shelf.items.map { it.archiveID })
            } else {
                db.shelf(shelf.id, 32, allowStandaloneTV = shelf.category == "tv-series")
            }
            // Home shows PROFESSIONAL posters only — the iOS/web rule, applied
            // here so a frame-grab cover never leads a shelf (owner 2026-08-31:
            // "only professional posters should show up on the Home Screen").
            // A shelf that cannot field 6 of them hides rather than pad itself.
            val taken = claim(resolved.filter { it.hasProfessionalArtwork }, min = 6)
            if (taken.isNotEmpty()) shelves.add(shelf.title.ifEmpty { shelf.id } to taken)
        }

        // Hero: well-composed WIDE backdrops only — REQUIRE a real backdrop, never a cropped 2:3
        // poster or frame-grab cover. The hero hides if none qualify (owner 2026-06-29).
        // The hero needs backdropURL and synopsis, which a LIST row does not
        // carry — shelves are built from the `items` columns so Home can draw
        // without decoding a thousand blobs. So resolve the FULL item for a
        // small pool of candidates: ~40 decodes instead of a thousand, and the
        // hero gets its backdrop and description back. (Without this it filtered
        // on a null backdrop and came up empty — a banner that silently
        // disappeared while every shelf still rendered.)
        //
        // The candidates were the FIRST 40 items in shelf order, with no
        // shuffle anywhere, so the hero was the same six films on every
        // launch — for good. (Found 2026-09-06 while fixing the identical
        // defect on Roku, where the owner reported it: "the same films every
        // single time I open the app".) tvOS has drawn from a deep
        // popularity window and shuffled the whole pool since 2026-06-29;
        // this brings Android to the same rule.
        //
        // The order matters for COST, not just variety. `backdropURL` lives
        // only in the item_json blob — it is not an `items` column — so it
        // cannot be filtered on cheaply. Shuffle the cheap LIST rows first,
        // then decode a bounded slice of them: 60 decodes, a different 60
        // each launch, instead of a thousand (the load-perf lesson that took
        // Google TV cold start from 32s to 6.3s).
        val heroSeed = System.currentTimeMillis()
        val heroPool = db.browse(
            sort = BrowseSort.POPULAR, limit = 1500, homeOnly = true,
        ).filter { it.hasProfessionalArtwork }
            .distinctBy { it.archiveID }
        val heroCandidates = heroPool.shuffled(Random(heroSeed)).take(60)
        val hero = db.itemsByIDs(heroCandidates.map { it.archiveID })
            .filter { it.backdropURL != null }
            // itemsByIDs does not promise the order it was asked in, so shuffle
            // again rather than let an id ordering decide which six lead.
            .shuffled(Random(heroSeed))
            .take(6)

        val pdYear = Calendar.getInstance().get(Calendar.YEAR) - 95
        // Category tiles count-gate >=30 (the apps' rule — a near-empty grid
        // never ships behind a tile).
        val categories = featured?.categories.orEmpty()
            .filter { db.browseCount(contentType = it.id) >= 30 }
        qmark("queries:begin")
        val built = HomePayload(
            hero = hero,
            continueWatching = continueWatching,
            shelves = shelves,
            topRated = claim(db.topRated().filter { it.hasProfessionalArtwork }),
            watchingNow = claim(db.watchingNow().filter { it.hasProfessionalArtwork }),
            communityFavorites = claim(db.communityFavorites().filter { it.hasProfessionalArtwork }),
            mostDiscussed = claim(db.mostDiscussed().filter { it.hasProfessionalArtwork }),
            hiddenGems = claim(db.hiddenGems(40).filter { it.hasProfessionalArtwork }),
            directorShelves = db.topDirectors().mapNotNull { d ->
                val films = claim(db.byDirector(d).filter { it.hasProfessionalArtwork }, min = 6)
                if (films.isNotEmpty()) d to films else null
            },
            publicDomainYear = pdYear,
            publicDomainDay = claim(db.browse(year = pdYear, limit = 120).filter { it.hasProfessionalArtwork }),
            categories = categories,
            decades = db.decadeCounts(),
            loaded = true,
        )
        held.value = built
        value = built
        qmark("producer:done")
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(container: AppContainer, nav: Nav) {
    val payload by rememberHomePayload(container)

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
                        subtitle = "Newly free for everyone this year — tap to explore past years",
                        onHeader = {
                            nav.push(
                                Route.Filtered(
                                    title = "Public Domain by year",
                                    year = payload.publicDomainYear,
                                    pdExplorer = true,
                                ),
                            )
                        },
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
            BackdropImage(
                url = item.backdropURL,
                contentDescription = item.title,
                accent = item.accentColor,
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
