package app.archivewatch.android.data

import android.net.Uri
import app.archivewatch.android.BuildConfig

/**
 * "Something wrong with this film?" (2026-09-26, the Orphaned Films research):
 * a pre-filled GitHub issue form carrying only what identifies the report —
 * the film and where it was seen. Nothing is sent until the viewer submits it.
 * Short, because a television shows it as a QR code. The web, Apple and Roku
 * build the same URL.
 */
object FilmProblem {
    fun url(archiveID: String, television: Boolean): String =
        Uri.parse("https://github.com/bhwilkoff/Archive-Watch/issues/new").buildUpon()
            .appendQueryParameter("template", "film-problem.yml")
            .appendQueryParameter("film", archiveID)
            .appendQueryParameter("where",
                (if (television) "Android TV " else "Android ") + BuildConfig.VERSION_NAME)
            .build().toString()
}
