package app.archivewatch.android.ui.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Celebration
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.data.PlaySpec
import app.archivewatch.android.data.QueueEntry
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route

/**
 * Party Play (the tvOS immersive mode, ported): muted background eye-candy —
 * COLOR, SHORT (≤15 min so the wall keeps changing), visually-engaging by
 * subject, most-visual first, shuffled per visit. Playback starts SILENT and
 * never persists progress; the player options panel unmutes.
 */
private val PARTY_VISUAL_KEYWORDS = listOf(
    "abstract", "experimental", "avant-garde", "avant garde", "psychedelic",
    "kaleidoscope", "surreal", "animation", "animated", "cartoon", "color",
    "colour", "technicolor", "dance", "ballet", "music", "musical", "light",
    "fireworks", "nature", "scenic", "travelogue", "landscape", "flowers",
    "garden", "ocean", "underwater", "aquarium", "space", "nasa", "aurora",
    "fractal", "mandala", "op art", "oil", "liquid", "paint", "art", "visual",
    "fantasia", "rhythm", "geometric", "neon", "carnival", "parade",
)

private suspend fun partyLineup(container: AppContainer): List<CatalogItem> {
    val db = container.catalog.awaitDb()
    // full = true: this lineup filters on downloadURL and colorMode, which a
    // list row does not carry. Without it the party would be silently empty.
    val raw = db.browse(contentType = "animation", limit = 250, full = true) +
        db.browse(contentType = "short-film", limit = 250, full = true) +
        db.browse(genre = "Animation", limit = 120, full = true)
    val seen = HashSet<String>()
    val scored = mutableListOf<Pair<CatalogItem, Int>>()
    for (it in raw) {
        if (it.downloadURL == null) continue
        if (it.hasDesignedArtwork != true) continue
        if (it.isSilent) continue
        if (it.colorMode == "bw") continue
        val r = it.runtimeSeconds
        if (r != null && r > 15 * 60) continue
        if (!seen.add(it.archiveID)) continue
        val blob = (it.genres + it.subjects + listOf(it.title))
            .joinToString(" ") { s -> s.lowercase() }
        val hits = PARTY_VISUAL_KEYWORDS.count { k -> k in blob }
        val animBoost = if (it.contentType == "animation") 2 else 0
        scored.add(it to (hits * 3 + animBoost + (it.popularityScore ?: 0) / 25))
    }
    return scored.sortedByDescending { it.second }.take(220).map { it.first }.shuffled()
}

@Composable
fun TvPartyScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val pool by produceState<List<CatalogItem>?>(null, dbVersion) {
        value = partyLineup(container)
    }
    val startFocus = remember { FocusRequester() }
    ClaimInitialFocus(startFocus, key = pool != null)

    val items = pool
    if (items == null) {
        TvMessage("Mixing the party reel…")
        return
    }
    if (items.isEmpty()) {
        TvMessage("Nothing colorful and short enough is in the catalog right now.")
        return
    }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            top = TvDims.OverscanV * 2, bottom = TvDims.OverscanV * 2,
        ),
    ) {
        item(key = "head") {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = TvDims.OverscanH),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    "Party Play",
                    fontSize = 32.sp, fontWeight = FontWeight.Medium, color = Color.White,
                )
                Text(
                    "A silent wall of color for the room — short, bright films that read " +
                        "well without sound. Unmute anytime from the player options.",
                    fontSize = 14.sp, color = Color(0xFF9A9A9A),
                    modifier = Modifier.padding(top = 8.dp, bottom = 22.dp),
                )
                Box(
                    Modifier
                        .tvFocusable(
                            onClick = {
                                val queue = items.mapNotNull { it2 ->
                                    it2.downloadURL?.let { u ->
                                        QueueEntry(id = it2.archiveID, title = it2.title, url = u)
                                    }
                                }
                                val first = items.first()
                                nav.push(
                                    Route.Player(
                                        PlaySpec(
                                            id = first.archiveID,
                                            title = first.title,
                                            url = first.downloadURL!!,
                                            queue = queue,
                                            persistProgress = false,
                                            startMuted = true,
                                        ),
                                    ),
                                )
                            },
                            focusRequester = startFocus,
                            shape = RoundedCornerShape(28.dp),
                        )
                        .background(Color(0xFFFF5C35), RoundedCornerShape(28.dp))
                        .padding(horizontal = 34.dp, vertical = 14.dp),
                ) {
                    androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Celebration, null, tint = Color.Black,
                            modifier = Modifier.size(20.dp))
                        Text("Start Party Play", fontSize = 16.sp, fontWeight = FontWeight.Medium,
                            color = Color.Black, modifier = Modifier.padding(start = 10.dp))
                    }
                }
            }
        }
        item(key = "mix") {
            Column(Modifier.padding(top = 30.dp)) {
                TvShelfRow(
                    "What's in the mix",
                    items.take(18),
                    onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
                )
            }
        }
    }
}
