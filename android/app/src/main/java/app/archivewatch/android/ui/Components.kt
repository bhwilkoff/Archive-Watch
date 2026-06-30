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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.theme.BrandSurface
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
        AsyncImage(
            model = item.posterURL,
            contentDescription = item.title,
            contentScale = ContentScale.Crop,
            onError = { failed = 1 },
            modifier = modifier,
        )
    } else {
        PosterTitleCard(item, modifier)
    }
}

/** The brand placeholder card (Decision 013 typographic poster) — accent gradient + centered
 *  title. The guaranteed non-blank fallback. */
@Composable
fun PosterTitleCard(item: CatalogItem, modifier: Modifier = Modifier) {
    val accent = when (item.contentType) {
        "tv-series", "tv-special" -> Color(0xFF2D5BFF)
        "silent-film" -> Color(0xFFC9A66B)
        "animation" -> Color(0xFFFF4D8D)
        "newsreel" -> Color(0xFF8A8F98)
        "documentary" -> Color(0xFF3FA796)
        "ephemeral" -> Color(0xFF7C5BBA)
        "short-film" -> Color(0xFFE8A317)
        else -> Color(0xFFFF5C35)
    }
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

/** 2:3 poster + two text lines — the one content tile (density rule). */
@Composable
fun PosterTile(
    item: CatalogItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.clickable(onClick = onClick)) {
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
) {
    if (items.isEmpty()) return
    Column {
        SectionHeader(title, subtitle)
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
fun EmptyState(message: String, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
