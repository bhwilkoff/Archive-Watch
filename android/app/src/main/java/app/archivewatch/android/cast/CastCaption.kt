package app.archivewatch.android.cast

/**
 * A subtitle track as handed to a Cast receiver.
 *
 * Lives in `main` (not a flavor) so both `CastSupport` twins share one type and
 * call sites stay flavor-agnostic — the amazon flavor takes the same argument
 * and ignores it (docs/TV-DESIGN.md §6.6).
 *
 * [url] must be the PUBLISHED https url. The receiver fetches subtitles itself,
 * so anything device-local is useless to it.
 */
data class CastCaption(
    val lang: String,
    val label: String,
    val url: String,
)
