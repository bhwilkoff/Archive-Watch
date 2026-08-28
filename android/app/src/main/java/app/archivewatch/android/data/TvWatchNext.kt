package app.archivewatch.android.data

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram
import app.archivewatch.android.ui.tv.isTelevision

/**
 * Google TV home-screen "Continue Watching" (the Top Shelf analogue, PARITY
 * §8). TV-DESIGN §1.4 binds: what we publish is the VIEWER'S OWN resume
 * state — never a recommendation model's opinion. One row per film, keyed by
 * archiveID through internalProviderId; the card deep-links back into the
 * app's Detail page, where Play resumes.
 *
 * Everything is best-effort behind runCatching: the WatchNext provider exists
 * on Google TV / Android TV but not on every TV-shaped device (Fire TV ships
 * its own launcher), and a launcher hiccup must never take playback down
 * with it.
 */
object TvWatchNext {

    fun publishResume(
        context: Context,
        archiveID: String,
        title: String,
        posterURL: String?,
        positionMs: Long,
        durationMs: Long,
    ) {
        if (!context.isTelevision()) return
        runCatching {
            val program = WatchNextProgram.Builder()
                .setType(TvContractCompat.WatchNextPrograms.TYPE_MOVIE)
                .setWatchNextType(TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE)
                .setInternalProviderId(archiveID)
                .setTitle(title)
                .setLastEngagementTimeUtcMillis(System.currentTimeMillis())
                .setLastPlaybackPositionMillis(positionMs.toInt())
                .setDurationMillis(durationMs.toInt())
                .setIntentUri(Uri.parse("archivewatch://item/$archiveID"))
                .apply { posterURL?.let { setPosterArtUri(Uri.parse(it)) } }
                .build()
            val existing = findRow(context, archiveID)
            if (existing != null) {
                val n = context.contentResolver.update(
                    ContentUris.withAppendedId(
                        TvContractCompat.WatchNextPrograms.CONTENT_URI, existing,
                    ),
                    program.toContentValues(), null, null,
                )
                android.util.Log.i("AWTV", "watchNext update $archiveID rows=$n")
            } else {
                val uri = context.contentResolver.insert(
                    TvContractCompat.WatchNextPrograms.CONTENT_URI,
                    program.toContentValues(),
                )
                android.util.Log.i("AWTV", "watchNext insert $archiveID -> $uri")
            }
        }.onFailure { android.util.Log.w("AWTV", "watchNext publish failed: $it") }
    }

    /** A finished film leaves the launcher row (>=95% is the app's own
     *  completion rule, UserStateStore.completedIDs). */
    fun remove(context: Context, archiveID: String) {
        if (!context.isTelevision()) return
        runCatching {
            findRow(context, archiveID)?.let { id ->
                context.contentResolver.delete(
                    ContentUris.withAppendedId(
                        TvContractCompat.WatchNextPrograms.CONTENT_URI, id,
                    ),
                    null, null,
                )
            }
        }
    }

    private fun findRow(context: Context, archiveID: String): Long? {
        context.contentResolver.query(
            TvContractCompat.WatchNextPrograms.CONTENT_URI,
            arrayOf(
                TvContractCompat.WatchNextPrograms._ID,
                TvContractCompat.WatchNextPrograms.COLUMN_INTERNAL_PROVIDER_ID,
            ),
            null, null, null,
        )?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(1) == archiveID) return c.getLong(0)
            }
        }
        return null
    }
}
