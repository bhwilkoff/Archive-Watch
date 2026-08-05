package app.archivewatch.android.ui.tv

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * The focus contract of docs/TV-DESIGN.md §3, expressed as reusable modifiers.
 *
 * Everything here exists because an unfocusable or ambiguously-focused element
 * is not a cosmetic problem on a TV — it is an unreachable feature, and it
 * fails Google's TV-DP outright.
 */

/**
 * Keys that mean "activate" on a remote. Some OEM remotes and the emulator send
 * ENTER, others DPAD_CENTER, and Fire remotes can send NUMPAD_ENTER. Accept all
 * three — a card that answers only one of them reads as broken.
 */
private val SELECT_KEYS = setOf(Key.DirectionCenter, Key.Enter, Key.NumPadEnter)

/**
 * Make any composable a first-class TV citizen: focusable, visibly focused by
 * **scale + ring + lift** (§3.2 — colour alone is never sufficient at ten feet,
 * and fails for colour-blind viewers on a bright panel), and activatable from
 * the remote.
 *
 * @param onClick invoked on select. Wired through [onKeyEvent] as well as any
 *   outer `clickable`, because `clickable` does not fire for D-pad select on
 *   every OEM remote.
 * @param focusRequester attach to claim initial focus (§3.1).
 * @param onFocused fires when this element gains focus — used by rows to keep
 *   the focused tile scrolled into view (§3.3).
 */
@Composable
fun Modifier.tvFocusable(
    onClick: () -> Unit,
    focusRequester: FocusRequester? = null,
    shape: RoundedCornerShape = RoundedCornerShape(10.dp),
    ringColor: Color = Color.White,
    scaleWhenFocused: Float = TvDims.FocusScale,
    onFocused: () -> Unit = {},
    /**
     * §3.4 — where Left should go when this element is the leftmost in a lazy
     * row (Compose focus search will not cross out of it).
     *
     * Handled HERE, inside the one key handler this element owns, rather than
     * as a separate Modifier.onKeyEvent wrapped around tvFocusable. That
     * arrangement puts two key handlers on opposite sides of the focus node and
     * the SELECT key stopped reaching onClick entirely — verified on the
     * emulator, where every column-0 key of the on-screen keyboard was dead
     * while other columns typed fine.
     */
    exitLeftTo: FocusRequester? = null,
    /** Label for the focus trace (see [TvFocusLogging]); defaults to the caller. */
    focusTag: String = "focusable",
): Modifier {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(
        targetValue = if (focused) scaleWhenFocused else 1f,
        animationSpec = tween(durationMillis = 120),
        label = "tvFocusScale",
    )
    val interaction = remember { MutableInteractionSource() }

    return this
        .scale(scale)
        .shadow(
            elevation = if (focused) TvDims.FocusElevation else 0.dp,
            shape = shape,
            clip = false,
        )
        .border(
            width = if (focused) TvDims.FocusRing else 0.dp,
            color = if (focused) ringColor else Color.Transparent,
            shape = shape,
        )
        .onFocusChanged {
            focused = it.isFocused
            if (it.isFocused) {
                if (TvFocusLogging) android.util.Log.i("AWFOCUS", focusTag)
                onFocused()
            }
        }
        .then(focusRequester?.let { Modifier.focusRequester(it) } ?: Modifier)
        .focusable(interactionSource = interaction)
        .onKeyEvent { ev ->
            if (ev.type != KeyEventType.KeyUp) return@onKeyEvent false
            when {
                ev.key in SELECT_KEYS -> { onClick(); true }
                ev.key == Key.DirectionLeft && exitLeftTo != null ->
                    runCatching { exitLeftTo.requestFocus() }.isSuccess
                else -> false
            }
        }
}

/**
 * §3.1 — something is ALWAYS focused. On entering a surface, focus is claimed
 * imperatively; leaving it to a default is unreliable across OEMs and strands
 * the user holding a remote that does nothing.
 *
 * Retries briefly because the target is usually inside a lazy list that has not
 * composed its first item on the frame the screen appears.
 */
@Composable
fun ClaimInitialFocus(requester: FocusRequester, key: Any? = Unit) {
    LaunchedEffect(key) {
        repeat(12) {
            if (runCatching { requester.requestFocus() }.isSuccess) return@LaunchedEffect
            delay(50)
        }
    }
}

/**
 * A focus anchor: an invisible focusable that gives a surface a guaranteed
 * initial target while its real content is still loading, so a loading state
 * still satisfies §3.1 instead of dropping focus into the void.
 */
@Composable
fun FocusAnchor(requester: FocusRequester, modifier: Modifier = Modifier) {
    Box(modifier.focusRequester(requester).focusable())
}
