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
    val seriesID: String? = null,
    val episodesCount: Int? = null,
) {
    // Derived predicates mirrored from the Swift model (contract §7).
    val hasDesignedArtwork: Boolean
        get() = hasRealArtwork ?: (artworkSource != null && artworkSource != "archive")
    val hasProfessionalArtwork: Boolean
        get() = hasDesignedArtwork && artworkSource != "generated"
    val isSilent: Boolean
        get() = isSilentFilm ?: (contentType == "silent-film")

    /** Poster fallback chain (contract §8): posterURL → Archive thumb. */
    val resolvedPosterURL: String
        get() = posterURL ?: archiveThumb
    val archiveThumb: String
        get() = "https://archive.org/services/img/$archiveID"
}

@Serializable
data class CastMember(
    val name: String,
    val character: String? = null,
    val order: Int = 0,
    val profilePath: String? = null,
) {
    /** profilePath may be a bare TMDb path — prefix w185 (contract §7). */
    val profileURL: String?
        get() = profilePath?.let {
            if (it.startsWith("http")) it else "https://image.tmdb.org/t/p/w185$it"
        }
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
    val url: String,
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
