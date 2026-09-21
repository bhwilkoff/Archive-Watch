package app.archivewatch.android.studio

/**
 * A full-frame graphic that REPLACES the programme: "Starting soon",
 * "Intermission", "Thanks for watching".
 *
 * A PORT of Apple's `StudioOverlay.Card` — same three cases, same headlines and
 * details word for word, because a host who sets an intermission on a phone and
 * on a Mac is showing their audience the same card
 * (`cross-platform-parity-discipline`). Cards existed on macOS and iOS and
 * NOWHERE ELSE; tvOS has none either, and that one stays open because Rule
 * 8.8c settles the television's only live surface as "two channels, a
 * rotation, and nothing else".
 */
sealed class StudioCard {
    data class StartingSoon(val secondsRemaining: Int) : StudioCard()
    data object Intermission : StudioCard()
    data object Ending : StudioCard()

    val headline: String
        get() = when (this) {
            is StartingSoon -> "Starting soon"
            is Intermission -> "Intermission"
            is Ending -> "Thanks for watching"
        }

    val detail: String
        get() = when (this) {
            is StartingSoon ->
                if (secondsRemaining > 0) clock(secondsRemaining) else "any moment now"
            is Intermission -> "back shortly"
            is Ending -> "archivewatch.org"
        }

    /**
     * NAME THE FILM on a card someone might arrive at — §2.1's argument, and
     * the one thing a generic "starting soon" card cannot say. Not on the
     * ending card, where the film is over.
     */
    val showsFilm: Boolean get() = this !is Ending

    /** The label a host reads in the panel. */
    val label: String
        get() = when (this) {
            is StartingSoon -> "Starting soon"
            is Intermission -> "Intermission"
            is Ending -> "Thanks for watching"
        }

    companion object {
        fun clock(seconds: Int): String {
            val m = seconds / 60
            val s = seconds % 60
            return "%d:%02d".format(m, s)
        }
    }
}
