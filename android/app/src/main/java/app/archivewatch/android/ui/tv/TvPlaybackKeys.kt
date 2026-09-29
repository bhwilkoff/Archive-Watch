package app.archivewatch.android.ui.tv

import androidx.compose.foundation.focusable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.media3.common.Player

/** How far the D-pad seeks per press (TV-PC). Matches the platform default so
 *  it feels like every other TV app the viewer uses. */
private const val SEEK_STEP_MS = 10_000L

/**
 * The TV playback key contract (docs/TV-DESIGN.md §5.2, Google TV-PC / TV-PP):
 *
 * - D-pad **center** toggles play/pause
 * - D-pad **left/right** rewind / fast-forward
 * - the dedicated media keys (PLAY_PAUSE, PLAY, PAUSE, REWIND, FAST_FORWARD)
 *   act during playback — TV-PP specifically requires PLAY_PAUSE to *toggle*
 *
 * Attached to the player surface itself so it works even while the transport
 * controller is hidden, which is exactly when a viewer reaches for these keys.
 */
@Composable
fun Modifier.tvPlaybackKeys(
    player: Player,
    onInteraction: () -> Unit = {},
    onMenu: () -> Unit = {},
    /** A channel is playing: Up/Down (and CH+/CH-) change channel, -1 the
     *  row above, +1 the row below, as on Apple TV. */
    onChannel: ((Int) -> Unit)? = null,
): Modifier {
    val requester = remember { FocusRequester() }
    // A held Select opens the options panel (the Android TV long-press), and
    // its release must not also toggle playback.
    val heldSelect = remember { booleanArrayOf(false) }

    // §3.1 — the player surface must hold focus or the keys never arrive.
    ClaimInitialFocus(requester, key = player)

    return this
        .focusRequester(requester)
        .focusable()
        .onKeyEvent { ev ->
            val select = ev.key == Key.DirectionCenter || ev.key == Key.Enter || ev.key == Key.NumPadEnter
            if (ev.type == KeyEventType.KeyDown && select && ev.nativeKeyEvent.repeatCount == 1) {
                heldSelect[0] = true
                onMenu()
                return@onKeyEvent true
            }
            if (ev.type != KeyEventType.KeyUp) return@onKeyEvent false
            if (select && heldSelect[0]) { heldSelect[0] = false; return@onKeyEvent true }
            if (onChannel != null) {
                when (ev.key) {
                    Key.DirectionUp, Key.ChannelDown -> { onInteraction(); onChannel(-1); return@onKeyEvent true }
                    Key.DirectionDown, Key.ChannelUp -> { onInteraction(); onChannel(1); return@onKeyEvent true }
                    else -> {}
                }
            }
            // Every handled key is an interaction — the player screen uses it
            // to show its overlay (Media3's own controller is never shown on
            // TV, so its visibility listener never fires here).
            when (ev.key) {
                Key.DirectionCenter, Key.Enter, Key.NumPadEnter, Key.MediaPlayPause,
                Key.MediaPlay, Key.MediaPause, Key.DirectionLeft, Key.MediaRewind,
                Key.DirectionRight, Key.MediaFastForward,
                Key.MediaNext, Key.MediaPrevious,
                Key.MediaSkipForward, Key.MediaSkipBackward -> onInteraction()
                else -> {}
            }
            when (ev.key) {
                Key.DirectionCenter, Key.Enter, Key.NumPadEnter, Key.MediaPlayPause -> {
                    // TV-PP: a single key that TOGGLES, never one that only plays.
                    if (player.isPlaying) player.pause() else player.play()
                    true
                }
                Key.MediaPlay -> { player.play(); true }
                Key.MediaPause -> { player.pause(); true }
                Key.DirectionLeft, Key.MediaRewind -> {
                    player.seekTo((player.currentPosition - SEEK_STEP_MS).coerceAtLeast(0))
                    true
                }
                Key.DirectionRight, Key.MediaFastForward -> {
                    val end = player.duration
                    val target = player.currentPosition + SEEK_STEP_MS
                    player.seekTo(if (end > 0) target.coerceAtMost(end) else target)
                    true
                }
                // Episode binge (queue playback): the Media3 controller never
                // shows on TV, so its next/previous buttons are unreachable —
                // the media keys are the only manual advance a remote has.
                Key.MediaNext, Key.MediaSkipForward -> {
                    if (player.hasNextMediaItem()) { player.seekToNextMediaItem(); true } else false
                }
                Key.MediaPrevious, Key.MediaSkipBackward -> {
                    if (player.hasPreviousMediaItem()) { player.seekToPreviousMediaItem(); true } else false
                }
                // The player options panel (the tvOS transport-menu analogue):
                // UP is the native Android TV gesture for in-player options,
                // and the remote MENU key means the same thing.
                Key.DirectionUp, Key.Menu -> { onMenu(); true }
                // Back is NOT handled here — §1.7 keeps it sacred, so it falls
                // through to the route's BackHandler and exits the player.
                else -> false
            }
        }
}
