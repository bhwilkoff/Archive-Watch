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
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.channels.Channel
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

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

    /**
     * The ONE sentence a guest's player shows, or null (SHAREPLAY §11.6.1a) —
     * the same three as Apple's `StudioRoomNotice` and the web's
     * `#player-note`: the guest moved the film (3 s, after the room has put it
     * back), the host ended the room, or joining failed. Nothing while a
     * guest is in step.
     */
    private var noticeState by mutableStateOf<String?>(null)
    var notice: String?
        get() = noticeState
        private set(value) {
            // The same line Apple's follower writes, so a device run can be read.
            if (value != noticeState) android.util.Log.i("AWFOLLOW", "notice=${value ?: "none"}")
            noticeState = value
        }
    private var noticeJob: Job? = null
    /** When WE last moved the player, so our own seek/pause is not the guest's. */
    private var appliedAtMillis = 0L
    /** Seconds this device's last catch-up seek took; 0 until one is timed. */
    private var seekLeadSeconds = 0.0
    private var seekStartedMillis = 0L
    private var lastPaused = false
    private var listener: Player.Listener? = null
    private val wake = Channel<Unit>(Channel.CONFLATED)
    private var noticeScope: CoroutineScope? = null

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

    /** The room's film. Only a player for THIS film takes [pending]: backing
     *  out of it used to leave the code waiting, and the next, unrelated film
     *  was seeked and paused by the room (launch audit A16). */
    var pendingFilm: String? = null

    fun join(scope: CoroutineScope, player: Player, code: String,
             base: String = StudioSyncClient.LIVE) {
        stop(player)
        val c = StudioSyncClient(base)
        client = c
        noticeScope = scope
        job = scope.launch {
            try {
                val state = c.join(code)
                status = Status.Following(c.code ?: code, state.filmID)
                lastPaused = state.paused
            } catch (e: Exception) {
                val why = sentence(e)
                status = Status.Failed(why)
                // Said on the player: the film plays on alone, and a guest who
                // is not told would think they were in the room.
                say(why, null)
                return@launch
            }
            withContext(Dispatchers.Main) { watchForGuestMoves(player) }
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
                // Woken early by a guest's own move, so it is answered now
                // rather than at the next poll (up to 10 s).
                withTimeoutOrNull((delaySeconds * 1000).toLong()) { wake.receive() }
                if (!isActive) return@launch
                try {
                    val s = c.poll()
                    hostRate = s.rate
                    lastPaused = s.paused
                } catch (e: Exception) {
                    // A room that ENDED is not a failure to report as one:
                    // the host finished, which is a normal way to stop.
                    if (e is StudioSyncClient.JoinError.NoSuchRoom ||
                        e is StudioSyncClient.JoinError.Ended) {
                        status = Status.Ended
                        withContext(Dispatchers.Main) { unwatch(player) }
                        // The film keeps playing — it is the guest's now —
                        // and they are told they are no longer in step.
                        say("The host ended the room.", 8_000)
                        return@launch
                    }
                    // Anything else is transient. A poll that failed is a
                    // poll, not a reason to tear a viewer out of a film.
                    continue
                }
                withContext(Dispatchers.Main) {
                    val local = player.currentPosition / 1000.0
                    val correction = c.correction(local, !player.isPlaying) ?: return@withContext
                    android.util.Log.d("AWFOLLOW", "local=%.1f playing=%s correction=%s"
                        .format(local, if (player.isPlaying) "y" else "n", correction))
                    apply(correction, player)
                }
            }
        }
    }

    fun stop(player: Player? = null) {
        job?.cancel(); job = null
        noticeJob?.cancel(); noticeJob = null
        notice = null
        player?.let { unwatch(it) }
        val c = client
        client = null
        status = Status.Idle
        player?.setPlaybackSpeed(1f)
        if (c != null) CoroutineScope(Dispatchers.IO).launch { runCatching { c.leave() } }
    }

    private fun watchForGuestMoves(player: Player) {
        unwatch(player)
        val l = object : Player.Listener {
            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                if (!playWhenReady &&
                    reason == Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST) guestMoved(player)
            }
            override fun onPlaybackStateChanged(state: Int) {
                // A catch-up seek has finished when the player is READY again.
                if (state == Player.STATE_READY && seekStartedMillis != 0L) {
                    seekLeadSeconds = ((System.currentTimeMillis() - seekStartedMillis) / 1000.0)
                        .coerceIn(0.0, 3.0)
                    seekStartedMillis = 0L
                }
            }
            override fun onPositionDiscontinuity(
                old: Player.PositionInfo, new: Player.PositionInfo, reason: Int,
            ) {
                if (reason == Player.DISCONTINUITY_REASON_SEEK) guestMoved(player)
            }
        }
        listener = l
        player.addListener(l)
    }

    private fun unwatch(player: Player) {
        listener?.let { player.removeListener(it) }
        listener = null
    }

    private fun guestMoved(player: Player) {
        if (status !is Status.Following) return
        if (!isGuestMove(System.currentTimeMillis() - appliedAtMillis, lastPaused,
                         player.duration, player.currentPosition)) return
        say("The host controls the film.", 3_000)
        wake.trySend(Unit)
    }

    /**
     * Where a catch-up seek should land (SHAREPLAY §11.3): ahead of the host
     * by this device's own MEASURED seek time, because the host keeps playing
     * while the guest seeks — the same rule as Apple's follower and the
     * web's. Nothing until a seek has been timed (a guessed lead overshot in
     * the browser, §8.66), and nothing for a paused guest.
     */
    fun seekTarget(to: Double, playing: Boolean, leadSeconds: Double, hostRate: Double): Double =
        if (playing) to + leadSeconds * hostRate else to

    /**
     * Whether a pause or seek is the GUEST's: not one this follower made in
     * the last 1.5 s, not a host pause, and not the film reaching its end.
     */
    fun isGuestMove(sinceOwnMoveMillis: Long, hostPaused: Boolean,
                    durationMs: Long, positionMs: Long): Boolean {
        if (sinceOwnMoveMillis < 1_500) return false
        if (hostPaused) return false
        if (durationMs > 0 && positionMs >= durationMs - 1_000) return false
        return true
    }

    private fun say(text: String, forMillis: Long?) {
        noticeJob?.cancel()
        notice = text
        if (forMillis == null) return
        noticeJob = (noticeScope ?: CoroutineScope(Dispatchers.Main)).launch {
            delay(forMillis)
            notice = null
        }
    }

    /** Silently — this function is the whole of §11.2a on Android. */
    private fun apply(c: StudioSync.Correction, player: Player) {
        if (c is StudioSync.Correction.Seek ||
            (c is StudioSync.Correction.SetPaused && c.paused)) {
            appliedAtMillis = System.currentTimeMillis()
        }
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
            is StudioSync.Correction.Seek -> {
                seekStartedMillis = System.currentTimeMillis()
                player.seekTo((seekTarget(c.to, player.isPlaying, seekLeadSeconds, hostRate) * 1000).toLong())
            }
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
