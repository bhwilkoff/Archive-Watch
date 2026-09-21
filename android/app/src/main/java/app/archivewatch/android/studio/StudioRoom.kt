package app.archivewatch.android.studio

import java.security.SecureRandom

/**
 * Room codes — SHAREPLAY §11.6 / §11.8, the Kotlin side.
 *
 * **This is the THIRD implementation of one rule** (Swift, JavaScript in the
 * Worker, and now Kotlin), which is three chances for them to disagree. If
 * Swift maps a heard "oh" to 0 and this does not, a guest who types what they
 * heard reaches a different room and the failure reads as "the code doesn't
 * work" with nothing to point at. `StudioRoomTest` asserts the SAME input
 * table §8.28 and §8.29 use — the same discipline `StudioLayoutTest` applies
 * to the placement rects.
 *
 * Crockford Base32: it drops I, L, O and U — I and L confusable with 1, O
 * with 0, and U so a random code cannot spell something unfortunate — and
 * KEEPS 0 and 1, which is what makes the input mapping possible at all. An
 * alphabet that excluded both members of every confusable pair would have
 * nothing to map a mistyped O onto and would have to refuse it.
 */
object StudioRoom {

    const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    /**
     * FOUR. The risk is not how many codes exist, it is the chance a random
     * guess lands on a room somebody is in: at ten live rooms that is 1 in
     * 104,857, and one keystroke fewer on a remote is worth more than headroom
     * nobody will use. Past ~1,000 concurrent rooms this becomes 5 or 6.
     */
    const val CODE_LENGTH = 4

    private val random = SecureRandom()

    fun newCode(): String = buildString {
        repeat(CODE_LENGTH) { append(ALPHABET[random.nextInt(ALPHABET.length)]) }
    }

    /**
     * What a person typed, turned into the one canonical form, or null.
     *
     * Forgiving on purpose, because the input arrives BY EAR: somebody heard
     * it on a call and is typing it. Case is ignored, spaces and dashes are
     * ignored (people group what they read aloud), and the confusable glyphs
     * are MAPPED rather than refused — a listener who hears "oh" and types O
     * meant zero, and being told "invalid code" for that is a bad way to
     * start a film.
     */
    fun normalize(typed: String?): String? {
        if (typed == null) return null
        val out = StringBuilder()
        for (ch in typed.uppercase()) {
            when (ch) {
                ' ', '-', '_', '\t' -> continue
                'I', 'L' -> out.append('1')
                'O' -> out.append('0')
                'U' -> return null
                else -> {
                    if (!ALPHABET.contains(ch)) return null
                    out.append(ch)
                }
            }
        }
        return if (out.length == CODE_LENGTH) out.toString() else null
    }
}
