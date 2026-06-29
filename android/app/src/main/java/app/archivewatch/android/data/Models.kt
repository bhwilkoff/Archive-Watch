package app.archivewatch.android.data

import kotlinx.serialization.Serializable

/**
 * The catalog item, decoded from `item_json.json` per
 * docs/CATALOG-CONTRACT.md §7. Unknown keys are ignored (additive-fields
 * rule); pipeline-only keys (`excluded`, `rightsAudit`, …) have no
 * properties here on purpose.
 */
@Serializable
data class CatalogItem(
    val archiveID: String,
    val title: String = "",
    val year: Int? = null,
    val decade: Int? = null,
    val contentType: String = "feature-film",
    val genres: List<String> = emptyList(),
    val subjects: List<String> = emptyList(),
    val collections: List<String> = emptyList(),
    val director: String? = null,
    val cast: List<CastMember> = emptyList(),
    val synopsis: String? = null,
    val posterURL: String? = null,
    val backdropURL: String? = null,
    val artworkSource: String? = null,
    val hasRealArtwork: Boolean? = null,
    val downloadURL: String? = null,
    val runtimeSeconds: Int? = null,
    val popularityScore: Int? = null,
    val qualityScore: Int? = null,
    val isSilentFilm: Boolean? = null,
    val colorMode: String? = null,
    val rightsStatus: String? = null,
    val seriesID: String? = null,
    val episodesCount: Int? = null,
    // Episode-item linkage (contentType == "tv-episode", Decision 045): a playable
    // episode materialized as a first-class catalog item so it shares the same
    // favorite/playlist/share/Detail/search machinery as a film.
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
    val seriesTitle: String? = null,
    // Subtitle/caption tracks (tools/enrich_subtitles.py) — side-loaded onto the
    // Media3 player via SubtitleConfiguration. Additive + optional.
    val captions: List<Caption>? = null,
    // Community / usage signals harvested from archive.org
    // (tools/harvest_community_signals.py). Additive + optional.
    val downloads: Int? = null,
    val numFavorites: Int? = null,
    val avgRating: Double? = null,
    val numReviews: Int? = null,
    val viewsAllTime: Int? = null,
    val views30d: Int? = null,
    // Genuine reviews of the TITLE, pre-filtered in the pipeline
    // (tools/comment_fit.py) — never file-quality or inappropriate comments.
    val reviews: List<Review>? = null,
    // Metadata expansion (Decision 046 / docs/METADATA-EXPANSION.md): rich TMDb/OMDb
    // fields backfilled into the item_json blob (~41% of films). Additive + optional;
    // arrays mirror genres/collections (default-empty so a missing key never crashes).
    // keywords + studios are ALSO mirrored into the value-indexed item_keywords /
    // item_studios join tables for filtering (see CatalogDatabase.byKeyword/byStudio).
    val keywords: List<String> = emptyList(),
    val akaTitles: List<String> = emptyList(),
    val studios: List<String> = emptyList(),
    val originalTitle: String? = null,
    val writer: String? = null,
    val composer: String? = null,
    val cinematographer: String? = null,
    val franchise: String? = null,
    val tagline: String? = null,
    val releaseDate: String? = null,
    val awards: String? = null,
) {
    // Community display helpers (mirror the Swift Catalog.Item helpers).
    val viewsDisplay: String?
        get() = (viewsAllTime ?: downloads)?.takeIf { it > 0 }?.let { compact(it) }
    val favoritesDisplay: String?
        get() = numFavorites?.takeIf { it > 0 }?.let { compact(it) }
    val avgRatingDisplay: String?
        get() = avgRating?.takeIf { it > 0 }?.let { String.format(java.util.Locale.US, "%.1f", it) }
    val displayReviews: List<Review>
        get() = reviews.orEmpty().filter { !it.body.isNullOrEmpty() || !it.title.isNullOrEmpty() }

    private fun compact(n: Int): String = when {
        n >= 1_000_000 -> String.format(java.util.Locale.US, "%.1fM", n / 1_000_000.0)
        n >= 1_000 -> String.format(java.util.Locale.US, "%.1fK", n / 1_000.0)
        else -> n.toString()
    }

    // Derived predicates mirrored from the Swift model (contract §7).
    val hasDesignedArtwork: Boolean
        get() = hasRealArtwork ?: (artworkSource != null && artworkSource != "archive")
    val hasProfessionalArtwork: Boolean
        get() = hasDesignedArtwork && artworkSource != "generated"
    val isSilent: Boolean
        get() = isSilentFilm ?: (contentType == "silent-film")

    // Title-level identity for cross-shelf Home de-duplication: two uploads of the
    // same film share a title+year but differ in archiveID, so an archiveID-only
    // seen-set lets the same title repeat across shelves. Normalized title+year,
    // falling back to archiveID so distinct yearless same-titled items don't merge.
    // (Android has no imdbID column; title+year is the strongest available signal.)
    val dedupKey: String
        get() {
            val t = title.lowercase().filter { it.isLetterOrDigit() }
            return if (t.isNotEmpty() && year != null) "ty:$t|$year" else "id:$archiveID"
        }

    /** A first-class episode item (Decision 045); its seriesID points at the spine. */
    val isEpisode: Boolean get() = contentType == "tv-episode"

    /** "S1 · E17" / "Ep. 17" byline for an episode item, else null. */
    val episodeNumberLabel: String?
        get() = when {
            seasonNumber != null && episodeNumber != null -> "S$seasonNumber · E$episodeNumber"
            episodeNumber != null -> "Ep. $episodeNumber"
            else -> null
        }

    /** Poster fallback chain (contract §8): posterURL → Archive thumb. */
    val resolvedPosterURL: String
        get() = posterURL ?: archiveThumb
    val archiveThumb: String
        get() = "https://archive.org/services/img/$archiveID"

    /**
     * Whether Clip Studio (the Create feature) is offered for this item —
     * the Android twin of `Catalog.Item.isClippable` (CREATE-STUDIO-PLAN §2,
     * Decision 033). Defense in depth on top of Decision 027 (copyrighted
     * titles are already excluded upstream): only offer clipping for content
     * we can confidently call free. A playable video is required; rightsStatus
     * must be PD/CC or absent (null/"" → allowed, since the visible catalog is
     * PD/CC-only post-027). An explicit rights-reserved status is NOT clippable.
     */
    val isClippable: Boolean
        get() {
            if (downloadURL.isNullOrBlank()) return false
            val s = (rightsStatus ?: "").lowercase()
            return when (s) {
                "", "public_domain", "publicdomain", "public-domain",
                "cc0", "creative_commons" -> true
                else -> s.startsWith("cc") || s.contains("public")
            }
        }

    /** Canonical archive.org source page for provenance/attribution. */
    val sourceDetailsURL: String
        get() = "https://archive.org/details/$archiveID"

    /**
     * Burned-in provenance credit line for exported clips — the attribution
     * wedge (CREATE-STUDIO-PLAN §1). Public domain by default; names a CC
     * dedication when that's the right.
     */
    val clipCreditLine: String
        get() {
            val rights = if ((rightsStatus ?: "").lowercase().contains("creative"))
                "Creative Commons" else "Public Domain"
            return "archivewatch.org · $rights"
        }
}

@Serializable
data class CastMember(
    val name: String,
    val character: String? = null,
    val order: Int = 0,
    val profilePath: String? = null,
    // TMDb person id (Decision 046) — decoded for future "more by this actor" /
    // person deep-links; Android has no Callsheet integration so it's unused today.
    val tmdbPersonID: Int? = null,
) {
    /** profilePath may be a bare TMDb path — prefix w185 (contract §7). */
    val profileURL: String?
        get() = profilePath?.let {
            if (it.startsWith("http")) it else "https://image.tmdb.org/t/p/w185$it"
        }
}

/** A side-loadable subtitle/caption track (tools/enrich_subtitles.py).
    Media3 plays SRT + VTT natively via SubtitleConfiguration. */
@Serializable
data class Caption(
    val lang: String,
    val label: String? = null,
    val format: String = "srt",
    val url: String,
    val source: String? = null,
) {
    val displayLabel: String get() = label ?: lang.uppercase()
}

/** A genuine review of the title, already pipeline-filtered (comment_fit.py). */
@Serializable
data class Review(
    val reviewer: String? = null,
    val title: String? = null,
    val body: String? = null,
    val stars: Int? = null,
    val date: String? = null,
) {
    val displayName: String get() = reviewer?.takeIf { it.isNotBlank() } ?: "Archive viewer"
}

// --- featured.json (contract §6.1) ---

@Serializable
data class Featured(
    val version: Int = 1,
    val categories: List<FeaturedCategory> = emptyList(),
    val shelves: List<FeaturedShelf> = emptyList(),
    // Editorial demotion (curate dashboard): these series ids sort LAST in
    // every TV list — still searchable/playable, never the marquee.
    val deprioritizedSeries: List<String> = emptyList(),
)

@Serializable
data class FeaturedCategory(
    val id: String,
    val displayName: String = "",
    val shortName: String? = null,
    val accent: String? = null,
    val posterAspect: String? = null,
    val note: String? = null,
)

@Serializable
data class FeaturedShelf(
    val id: String,
    val title: String = "",
    val subtitle: String? = null,
    val category: String? = null,
    val type: String = "dynamic",
    val items: List<FeaturedPick> = emptyList(),
    val limit: Int? = null,
)

@Serializable
data class FeaturedPick(
    val archiveID: String,
    val note: String? = null,
)

// --- series/{slug}.json (contract §6.3) ---

@Serializable
data class SeriesDetail(
    val version: Int = 2,
    val seriesID: String,
    val title: String = "",
    val yearStart: Int? = null,
    val yearEnd: Int? = null,
    val overview: String? = null,
    val posterURL: String? = null,
    val backdropURL: String? = null,
    val genres: List<String> = emptyList(),
    val networks: List<String> = emptyList(),
    val creator: String? = null,
    val seasons: List<SeriesSeason> = emptyList(),
    val episodesCount: Int? = null,
    val canonicalEpisodesCount: Int? = null,
    val cast: List<CastMember> = emptyList(),
)

@Serializable
data class SeriesSeason(
    val seasonNumber: Int? = null,
    val episodes: List<SeriesEpisode> = emptyList(),
)

@Serializable
data class SeriesEpisode(
    val archiveID: String? = null,
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
    val title: String? = null,
    val overview: String? = null,
    val stillURL: String? = null,
    val airDate: String? = null,
    val year: Int? = null,
    val runtimeSeconds: Int? = null,
    val downloadURL: String? = null,
)

/** What the player actually plays — an item or an episode. */
data class PlaySpec(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    // Synopsis shown in the player's title+description overlay (which fades with
    // the transport controls). Distinct from `subtitle` (lock-screen line).
    val description: String? = null,
    val url: String,
    // Side-loaded subtitle tracks (Decision 039) — Media3 plays SRT/VTT natively.
    val captions: List<Caption> = emptyList(),
    val runtimeSeconds: Int? = null,
    // Episode binge (the apps' auto-advance): the season's playable queue,
    // loaded as Media3 items so next/previous and end-of-item advance are
    // native player behavior.
    val queue: List<QueueEntry> = emptyList(),
    val queueIndex: Int = 0,
    // Channel join-in-progress: start the first item this far in.
    val startPositionMs: Long = 0,
    // Channel/lineup playback never persists resume progress (apps' rule).
    val persistProgress: Boolean = true,
)

/** One binge-queue entry (an episode). */
data class QueueEntry(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val url: String,
)


@kotlinx.serialization.Serializable
data class CollectionMetadataFile(
    val collections: List<CollectionMeta> = emptyList(),
)

@kotlinx.serialization.Serializable
data class CollectionMeta(
    val id: String,
    val title: String,
    val blurb: String? = null,
    val accent: String? = null,
    val category: String? = null,
)

