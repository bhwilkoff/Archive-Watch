package app.archivewatch.android.studio

import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The Android platform layer for SHAREPLAY §11: polls a room and APPLIES what
 * comes back to an ExoPlayer.
 *
 * §11.2a: nobody is ever asked to do anything. A guest whose host pauses
 * simply sees the film pause. This is the code that makes that true — the
 * thin caller `StudioSync` deliberately is not, so the rule stays testable
 * without a player and the player stays replaceable without the rule.
 *
 * The mirror of the Apple `StudioSyncFollower`, and the same two things that
 * would be silently wrong are handled the same way here.
 */
object StudioSyncFollower {

    sealed interface Status {
        data object Idle : Status
        data class Following(val code: String, val filmID: String) : Status
        data object Ended : Status
        data class Failed(val why: String) : Status
    }

    var status: Status = Status.Idle
        private set

    private var client: StudioSyncClient? = null
    private var job: Job? = null
    /** The rate the HOST is playing at, so a nudge is undone to the right
     *  value — a host watching at 1.25x would otherwise be corrected to
     *  normal speed every few seconds by the thing meant to keep them in
     *  step. */
    private var hostRate: Double = 1.0

    /** A code handed from the join surface to the player, which is the one
     *  place an ExoPlayer exists. */
    var pending: String? = null

    fun join(scope: CoroutineScope, player: Player, code: String,
             base: String = StudioSyncClient.LIVE) {
        stop(player)
        val c = StudioSyncClient(base)
        client = c
        job = scope.launch {
            try {
                val state = c.join(code)
                status = Status.Following(c.code ?: code, state.filmID)
            } catch (e: Exception) {
                status = Status.Failed(sentence(e))
                return@launch
            }
            // "I'm here", every 30 s, so the host sees friends arrive. A child
            // of this job, so it stops when following stops.
            val token = java.util.UUID.randomUUID().toString().replace("-", "")
            launch {
                while (isActive) {
                    c.sayHere(token)
                    delay(30_000)
                }
            }
            while (isActive) {
                val delaySeconds = c.nextPollDelaySeconds()
                delay((delaySeconds * 1000).toLong())
                if (!isActive) return@launch
                try {
                    val s = c.poll()
                    hostRate = s.rate
                } catch (e: Exception) {
                    // A room that ENDED is not a failure to report as one:
                    // the host finished, which is a normal way to stop.
                    if (e is StudioSyncClient.JoinError.NoSuchRoom ||
                        e is StudioSyncClient.JoinError.Ended) {
                        status = Status.Ended
                        return@launch
                    }
                    // Anything else is transient. A poll that failed is a
                    // poll, not a reason to tear a viewer out of a film.
                    continue
                }
                withContext(Dispatchers.Main) {
                    val local = player.currentPosition / 1000.0
                    val correction = c.correction(local, !player.isPlaying) ?: return@withContext
                    apply(correction, player)
                }
            }
        }
    }

    fun stop(player: Player? = null) {
        job?.cancel(); job = null
        val c = client
        client = null
        status = Status.Idle
        player?.setPlaybackSpeed(1f)
        if (c != null) CoroutineScope(Dispatchers.IO).launch { runCatching { c.leave() } }
    }

    /** Silently — this function is the whole of §11.2a on Android. */
    private fun apply(c: StudioSync.Correction, player: Player) {
        when (c) {
            is StudioSync.Correction.None ->
                // Back to the HOST's rate, not to 1. A nudge left in place is
                // a film that plays 3% fast for the rest of the show, and the
                // drift it was correcting is already gone.
                if (player.isPlaying && player.playbackParameters.speed.toDouble() != hostRate) {
                    player.playbackParameters = PlaybackParameters(hostRate.toFloat())
                }
            is StudioSync.Correction.Nudge ->
                player.playbackParameters = PlaybackParameters((hostRate * c.rate).toFloat())
            is StudioSync.Correction.Seek ->
                player.seekTo((c.to * 1000).toLong())
            is StudioSync.Correction.SetPaused ->
                if (c.paused) player.pause() else {
                    player.playbackParameters = PlaybackParameters(hostRate.toFloat())
                    player.play()
                }
        }
    }

    fun sentence(e: Throwable): String = when (e) {
        is StudioSyncClient.JoinError.BadCode ->
            "That is not a room code. They are four characters — ask the host to read it again."
        is StudioSyncClient.JoinError.NoSuchRoom ->
            "No room with that code. It may have ended, or a character may have been misheard."
        is StudioSyncClient.JoinError.Ended -> "That room has ended."
        else -> "Could not reach the room — ${e.message ?: e}"
    }
}
