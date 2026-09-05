package app.archivewatch.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.blur
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.theme.BrandSurface
import app.archivewatch.android.ui.tv.LocalIsTelevision
import app.archivewatch.android.ui.tv.tvFocusable
import coil3.compose.AsyncImage

/**
 * Poster with the contract §8 fallback chain, guaranteeing the slot is NEVER blank (owner: a
 * blank poster makes the app look broken): posterURL → Archive thumb (`services/img/{id}`) →
 * a typographic title card.
 */
@Composable
fun PosterImage(item: CatalogItem, modifier: Modifier = Modifier) {
    // Designed poster ONLY → (fail) the typographic title card. Never the archive.org services/img
    // thumbnail (owner 2026-06-29); the cover pipeline supplies real posters for art-less items.
    var failed by remember(item.archiveID) { mutableIntStateOf(0) }
    if (failed == 0 && item.hasDesignedArtwork && item.posterURL != null) {
        // The title card sits UNDER the poster while it loads, so a shelf whose
        // artwork is still in flight reads as a shelf of films, not a row of
        // blank boxes. A blank tile is what "stuck" looks like on a TV (owner,
        // Google TV: content in seconds, then a frozen-looking wait for art).
        // The poster crossfades over it; on error the card simply stays.
        Box(modifier) {
            PosterTitleCard(item, Modifier.matchParentSize())
            AsyncImage(
                model = item.posterURL,
                contentDescription = item.title,
                contentScale = ContentScale.Crop,
                onError = { failed = 1 },
                modifier = Modifier.matchParentSize(),
            )
        }
    } else {
        PosterTitleCard(item, modifier)
    }
}

/** Per-category semantic accent (Decision 013) — the shared brand palette, used by the title-card
 *  fallback and the backdrop-gradient fallback. */
val CatalogItem.accentColor: Color
    get() = when (contentType) {
        "tv-series", "tv-special", "tv-episode" -> Color(0xFF2D5BFF)
        "silent-film" -> Color(0xFFC9A66B)
        "animation" -> Color(0xFFFF4D8D)
        "newsreel" -> Color(0xFF8A8F98)
        "documentary" -> Color(0xFF3FA796)
        "ephemeral" -> Color(0xFF7C5BBA)
        "short-film" -> Color(0xFFE8A317)
        else -> Color(0xFFFF5C35)
    }

/** The brand placeholder card (Decision 013 typographic poster) — accent gradient + centered
 *  title. The guaranteed non-blank fallback. */
@Composable
fun PosterTitleCard(item: CatalogItem, modifier: Modifier = Modifier) {
    val accent = item.accentColor
    Box(
        modifier = modifier.background(
            Brush.linearGradient(listOf(accent.copy(alpha = 0.85f), Color(0xFF101010)))
        ),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            item.title,
            color = Color.White,
            style = MaterialTheme.typography.bodySmall,
            textAlign = TextAlign.Center,
            maxLines = 5,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(8.dp),
        )
    }
}

/**
 * Backdrop / hero / still image with a guaranteed non-blank fallback. A raw AsyncImage that
 * 404s or gets throttled renders an empty box; instead fail to a quiet brand gradient — NEVER the
 * archive.org services/img thumbnail (owner 2026-06-29). Used for heroes, Detail/Series backdrops,
 * and episode stills.
 */
@Composable
fun BackdropImage(
    url: String?,
    contentDescription: String? = null,
    accent: Color = Color(0xFFFF5C35),
    modifier: Modifier = Modifier,
    /** True when the image is a POSTER standing in for a backdrop. A 2:3
     *  poster crop-filled into a ~2.4:1 box is a pixelated slice of its middle
     *  (the Roku Detail lesson, 2026-09-04, and the Fire TV report before it).
     *  Soft = decode it tiny and let the upscale blur it, plus a real Gaussian
     *  blur on API 31+, so it becomes an ambient wash of the film's colour
     *  rather than a picture the viewer tries to read. */
    soft: Boolean = false,
) {
    var failed by remember(url) { mutableStateOf(false) }
    if (!failed && url != null) {
        val ctx = LocalContext.current
        val model: Any = if (soft) {
            coil3.request.ImageRequest.Builder(ctx)
                .data(url)
                // ~96 px wide: the bilinear upscale to the full box is the blur
                // on every API level; precision INEXACT lets Coil hand back a
                // small bitmap instead of insisting on the source size.
                .size(96, 54)
                .precision(coil3.size.Precision.INEXACT)
                .build()
        } else url
        AsyncImage(
            model = model,
            contentDescription = contentDescription,
            contentScale = ContentScale.Crop,
            onError = { failed = true },
            modifier = if (soft) modifier.blur(28.dp) else modifier,
        )
    } else {
        Box(
            modifier = modifier.background(
                Brush.linearGradient(listOf(accent.copy(alpha = 0.5f), Color(0xFF101010)))
            ),
        )
    }
}

/** Circular cast/crew avatar with a monogram fallback (raw AsyncImage left a blank circle when a
 *  profile image 404s). */
@Composable
fun AvatarImage(url: String?, name: String, modifier: Modifier = Modifier) {
    var failed by remember(url) { mutableStateOf(false) }
    if (!failed && url != null) {
        AsyncImage(
            model = url,
            contentDescription = name,
            contentScale = ContentScale.Crop,
            onError = { failed = true },
            modifier = modifier,
        )
    } else {
        Box(
            modifier = modifier.background(BrandSurface),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                name.firstOrNull()?.uppercase() ?: "?",
                color = Color.White,
                style = MaterialTheme.typography.titleMedium,
            )
        }
    }
}

/** 2:3 poster + two text lines — the one content tile (density rule). */
/**
 * The shared content tile.
 *
 * ⚠️ TV: `clickable` is a TOUCH affordance and gives NO D-pad focus. This one
 * component backs Surprise, Collections, Cartoon Mode, person filmographies and
 * every filtered grid, so leaving it touch-only made all of those surfaces
 * completely unreachable by remote (TV-DP) — including the destination the TV
 * Search "browse without typing" doors push to. Found by auditing for
 * `.clickable` after the same bug turned up in the Channels EPG.
 *
 * TV-native screens use TvPosterTile; this keeps the shared fall-through
 * screens operable until each gets its own ten-foot pass.
 */
@Composable
fun PosterTile(
    item: CatalogItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isTv = LocalIsTelevision.current
    Column(
        modifier = modifier.then(
            if (isTv) {
                Modifier.tvFocusable(
                    onClick = onClick,
                    ringColor = item.accentColor,
                    shape = RoundedCornerShape(10.dp),
                    focusTag = "tile:" + item.title.take(28),
                )
            } else {
                Modifier.clickable(onClick = onClick)
            },
        ),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(2f / 3f)
                .clip(RoundedCornerShape(8.dp))
                .background(BrandSurface),
        ) {
            PosterImage(item, Modifier.fillMaxSize())
        }
        Text(
            item.title,
            style = MaterialTheme.typography.bodySmall,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 4.dp),
        )
        item.year?.let {
            Text(
                it.toString(),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun SectionHeader(title: String, subtitle: String? = null) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        if (subtitle != null) {
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Horizontal poster rail — the Home/Detail shelf shape. */
@Composable
fun ShelfRow(
    title: String,
    items: List<CatalogItem>,
    onItem: (CatalogItem) -> Unit,
    subtitle: String? = null,
    onHeader: (() -> Unit)? = null,
) {
    if (items.isEmpty()) return
    Column {
        Box(
            if (onHeader != null) Modifier.clickable(onClick = onHeader) else Modifier,
        ) {
            SectionHeader(title, subtitle)
        }
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(items, key = { it.archiveID }) { item ->
                PosterTile(item, onClick = { onItem(item) }, modifier = Modifier.width(110.dp))
            }
        }
    }
}

@Composable
fun LoadingBox(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
fun EmptyState(message: String, modifier: Modifier = Modifier, onRetry: (() -> Unit)? = null) {
    Box(modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            if (onRetry != null) {
                androidx.compose.material3.TextButton(
                    onClick = onRetry,
                    modifier = Modifier.padding(top = 8.dp),
                ) { Text("Retry") }
            }
        }
    }
}

/** The content KIND as a shelf word, never the slug. Same table as tvOS and
 *  the Roku `KindLabel`, so the eyebrow reads identically on every screen. */
fun kindLabel(contentType: String): String = when (contentType) {
    "feature-film" -> "Feature Film"
    "silent-film" -> "Silent Era"
    "tv-series" -> "Classic TV"
    "tv-special" -> "Television"
    "tv-episode" -> "Episode"
    "animation" -> "Animation"
    "newsreel" -> "Newsreel"
    "documentary" -> "Documentary"
    "ephemeral" -> "Ephemera"
    "short-film" -> "Short Film"
    "commercial" -> "Commercial"
    else -> contentType.replace('-', ' ').replaceFirstChar { it.uppercase() }
}

/** Up to two CANONICAL genres for a meta line. The catalog's genres field
 *  mixes Title-Case genres (Drama, Film Noir) with lowercase TMDb descriptor
 *  tags ("comedy drama", "comedy of remarriage"); the descriptors duplicate
 *  the real genre in a second case and read as clutter, so only Title-Case
 *  entries are kept. */
fun metaGenres(genres: List<String>): List<String> =
    genres.filter { it.isNotBlank() && it.first().isUpperCase() }.take(2)

/** The category eyebrow: the kind in its accent, tracked small caps, above a
 *  title. It is the ONE place the kind is stated, so meta lines below it carry
 *  year, genres and rating instead of repeating it. */
@Composable
fun KindEyebrow(contentType: String, accent: Color, modifier: Modifier = Modifier) {
    Text(
        kindLabel(contentType).uppercase(),
        fontSize = 13.sp,
        letterSpacing = 2.sp,
        fontWeight = FontWeight.SemiBold,
        color = accent,
        modifier = modifier,
    )
}
