package app.archivewatch.android.studio

import kotlin.math.abs

/**
 * Keeping the film in sync without SharePlay — SHAREPLAY §11, the Kotlin side.
 *
 * Pure values, like the Swift original and for the same reason: this is the
 * part most likely to be quietly wrong, and it can be exercised with controls
 * on any machine with no network and no player.
 *
 * **Fourth implementation of one set of numbers** (Swift, the browser's
 * JavaScript, and now Kotlin — the Worker holds only the code rule).
 * `StudioSyncTest` asserts the SAME cases §8.27 and §8.32 do, the way
 * `StudioLayoutTest` pins the placement rects to what §8.22 printed.
 */
object StudioSync {

    /** Inside this, a shared watch feels together. */
    const val TOLERANCE_SECONDS = 0.150
    /** Beyond this a nudge would take longer than a viewer will accept. */
    const val SEEK_THRESHOLD_SECONDS = 2.0
    const val NUDGE_FAST = 1.03
    const val NUDGE_SLOW = 0.97
    const val POLL_FAST_SECONDS = 2.0
    const val POLL_IDLE_SECONDS = 10.0
    const val IDLE_AFTER_SECONDS = 60.0

    data class State(
        val filmID: String,
        val position: Double,
        /** The SERVER's clock when `position` was true — never a client's. */
        val atServerTime: Double,
        val rate: Double = 1.0,
        val paused: Boolean = false,
        val generation: Int = 1,
        /** The HOST's copy, `<archive item>/<file name>` — the file every guest
         *  plays (owner, 2026-09-26). Null from a host that predates it. */
        val copy: String? = null,
    ) {
        /**
         * Where the film should be at [serverNow].
         *
         * A PAUSED film does not advance — obvious, and the thing an
         * elapsed-time formula gets wrong the moment it forgets to ask.
         */
        fun expectedPosition(serverNow: Double): Double =
            if (paused) position
            else position + maxOf(0.0, serverNow - atServerTime) * rate
    }

    data class ClockSample(val sentAt: Double, val serverTime: Double, val receivedAt: Double) {
        val roundTrip: Double get() = maxOf(0.0, receivedAt - sentAt)
        /** Cristian's algorithm. */
        val offset: Double get() = serverTime - (sentAt + receivedAt) / 2
        /** The bound on [offset], which is WHY the fastest sample is the best. */
        val error: Double get() = roundTrip / 2
    }

    /**
     * THE SMALLEST ROUND TRIP, NEVER THE AVERAGE. The error bound is RTT/2, so
     * averaging mixes a good measurement with bad ones and throws the bound
     * away — a number you cannot state an error for is worse than a noisier
     * one you can.
     */
    fun bestOffset(samples: List<ClockSample>): ClockSample? = samples.minByOrNull { it.roundTrip }

    sealed interface Correction {
        data object None : Correction
        data class Nudge(val rate: Double) : Correction
        data class Seek(val to: Double) : Correction
        data class SetPaused(val paused: Boolean) : Correction
    }

    /**
     * What a guest's PLAYER should be made to do — applied by the app,
     * silently. Nobody is ever asked to pause or seek anything (§11.2a).
     *
     * A rate change is preferred to a seek for the reason Decision 081 gives
     * for captions: a correction may not rewind past the viewer. A seek is
     * visible and re-buffers; 3% is neither.
     */
    fun correction(
        localPosition: Double,
        localPaused: Boolean,
        state: State,
        serverNow: Double,
    ): Correction {
        // Run state first, and never eased: a host who pressed pause wants the
        // film stopped now.
        if (state.paused != localPaused) return Correction.SetPaused(state.paused)
        // A paused film cannot drift, but it can be on the wrong FRAME — the
        // host paused to talk about a shot (same rule as StudioSync.swift).
        if (state.paused) {
            return if (abs(state.position - localPosition) > TOLERANCE_SECONDS)
                Correction.Seek(state.position) else Correction.None
        }
        val drift = state.expectedPosition(serverNow) - localPosition   // + = behind
        val magnitude = abs(drift)
        if (magnitude <= TOLERANCE_SECONDS) return Correction.None
        if (magnitude >= SEEK_THRESHOLD_SECONDS) return Correction.Seek(state.expectedPosition(serverNow))
        return Correction.Nudge(if (drift > 0) NUDGE_FAST else NUDGE_SLOW)
    }

    /** Back off while nothing happens; snap back the moment it does. */
    fun pollInterval(secondsSinceGenerationChanged: Double): Double =
        if (secondsSinceGenerationChanged >= IDLE_AFTER_SECONDS) POLL_IDLE_SECONDS else POLL_FAST_SECONDS
}

/**
 * WHICH FILE A ROOM PLAYS, enforced where the player chooses one: while this
 * device is in a room for a film, [ArchiveVersions.preferredURL] returns the
 * HOST's copy — or the title's default for a host that predates it — never
 * this viewer's own saved choice. Owner, 2026-09-26: "There should be no way to
 * choose the wrong one via the four digit code." Copies of a title differ in
 * length, so the wrong copy is a different timeline. Mirrors Apple's
 * StudioRoomCopy and the Worker's normalizeCopy.
 */
object StudioRoomCopy {
    @Volatile private var active: Pair<String, String?>? = null
    private val ITEM = Regex("^[A-Za-z0-9._@:+-]{1,120}$")

    fun set(film: String, copy: String?) { active = film to copy }
    fun clear() { active = null }
    fun isActive(film: String): Boolean = active?.first == film

    /** What a player must play for [film], or null when not in a room for it. */
    fun url(film: String, fallback: String): String? {
        val room = active ?: return null
        if (room.first != film) return null
        return room.second?.let { urlFromPath(it) } ?: fallback
    }

    /** The archive.org URL for a room's copy — built here, so a room can only
     *  ever name a file on archive.org. */
    fun urlFromPath(path: String): String? {
        if (path.length > 520) return null
        val slash = path.indexOf('/')
        if (slash < 1) return null
        val item = path.substring(0, slash)
        val name = path.substring(slash + 1)
        if (!ITEM.matches(item) || name.isEmpty() || name.startsWith("/") || name.contains("..") ||
            name.contains('\\') || name.any { it.code < 0x20 }) return null
        val encoded = name.split('/').joinToString("/") {
            java.net.URLEncoder.encode(it, "UTF-8").replace("+", "%20")
        }
        return "https://archive.org/download/$item/$encoded"
    }

    /** Read a room and remember its copy, so the player built next plays it. */
    suspend fun prime(code: String): StudioSync.State? {
        val client = StudioSyncClient()
        return try {
            client.join(code).also { set(it.filmID, it.copy) }
        } catch (_: Exception) { null } finally { client.leave() }
    }
}
