package app.archivewatch.android.data

import android.net.Uri
import androidx.core.net.toUri
import app.archivewatch.android.BuildConfig

/**
 * "Something wrong with this film?" (2026-09-26, the Orphaned Films research):
 * archivewatch.org/report.html, which offers an email and the GitHub issue
 * form, carrying only what identifies the report: the film and where it was seen.
 * Short, because a television shows it as a QR code. The web, Apple and Roku
 * build the same URL.
 */
object FilmProblem {
    fun url(archiveID: String, television: Boolean): String =
        "https://archivewatch.org/report.html".toUri().buildUpon()
            .appendQueryParameter("film", archiveID)
            .appendQueryParameter("where",
                (if (television) "Android TV " else "Android ") + BuildConfig.VERSION_NAME)
            .build().toString()
}
