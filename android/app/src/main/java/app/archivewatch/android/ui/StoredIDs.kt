package app.archivewatch.android.ui

import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.UserPlaylist

/**
 * A viewer's records are kept under the id they were made with, and the build
 * merges duplicate uploads into one card every publish (Decision 085): a film
 * favorited as `X_1950` is shown as its survivor `X`. So a card's heart, its
 * playlist ticks and its history removal must act on the STORED id, or the
 * heart reads empty, a second favorite is added beside the first, and a
 * removal deletes nothing.
 */
suspend fun storedAliases(container: AppContainer, archiveID: String): Set<String> =
    setOf(archiveID) + (container.catalog.db?.mergedIDs(archiveID) ?: emptyList())

suspend fun isFavoriteStored(container: AppContainer, aliases: Set<String>): Boolean =
    aliases.any { container.userState.isFavorite(it) }

/** Returns whether the card is a favorite afterwards. */
suspend fun toggleFavoriteStored(container: AppContainer, archiveID: String, aliases: Set<String>): Boolean {
    val held = aliases.filter { container.userState.isFavorite(it) }
    if (held.isEmpty()) return container.userState.toggleFavorite(archiveID)
    held.forEach { container.userState.toggleFavorite(it) }
    return false
}

fun storedInPlaylist(pl: UserPlaylist, aliases: Set<String>): List<String> =
    pl.archiveIDs.filter { it in aliases }

suspend fun togglePlaylistStored(container: AppContainer, pl: UserPlaylist, archiveID: String, aliases: Set<String>) {
    val held = storedInPlaylist(pl, aliases)
    if (held.isEmpty()) container.userState.togglePlaylistItem(pl.id, archiveID)
    else held.forEach { container.userState.togglePlaylistItem(pl.id, it) }
}
