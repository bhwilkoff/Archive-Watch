package app.archivewatch.android.ui.tv

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.unit.dp

/**
 * TV is a RUNTIME BRANCH, not a build flavor and never a fork
 * (docs/TV-DESIGN.md §6.5, Decision 047).
 *
 * One `applicationId`, one AAB, one launcher activity — the data layer,
 * repositories, player engine and navigation routes are shared verbatim with
 * the phone build; only the composables differ. Forking would re-introduce
 * exactly the divergence Decision 028 forbids.
 */
fun Context.isTelevision(): Boolean {
    val ui = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
    if (ui?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true
    // Fire OS reports UI_MODE_TYPE_NORMAL on some devices, so fall back to the
    // leanback feature flags the launcher itself keys on.
    val pm = packageManager
    return pm.hasSystemFeature("android.software.leanback") ||
        pm.hasSystemFeature("android.hardware.type.television")
}

/**
 * Read by any composable that must adapt without threading a flag through every
 * signature. Defaults to false so a missing provider degrades to the phone UI,
 * never to a half-TV one.
 */
val LocalIsTelevision = compositionLocalOf { false }

/**
 * Verification aid, off unless an automated run turns it on
 * (`--ez aw_focus_log true`).
 *
 * On a TV, focus is the whole interaction model and it is INVISIBLE to a
 * screenshot — this session had a screenshot show a working EPG that was
 * unreachable, and a "broken" Surprise that was fine. A focus trace is the only
 * consistently trustworthy signal, so it is a permanent, cheap facility rather
 * than logging pasted in and ripped out each time.
 */
@Volatile
var TvFocusLogging: Boolean = false

/**
 * The nav rail's focus target (§3.4).
 *
 * Left from the LEFTMOST tile of a row must reach the rail, or the tabs are
 * unreachable by remote and TV-DP fails. Compose's own focus search does not
 * cross from a LazyRow's first item into a sibling container, and
 * `focusProperties { exit = ... }` is not delivered through the lazy list
 * either — both verified on the Android TV emulator. So rows request it
 * explicitly, and a CompositionLocal keeps that out of every signature.
 */
val LocalTvRailFocus = compositionLocalOf<androidx.compose.ui.focus.FocusRequester?> { null }

/**
 * Ten-foot design tokens (docs/TV-DESIGN.md §4). These are the binding numbers;
 * a surface that needs a value not listed here needs a rule change first.
 */
object TvDims {
    /** §4.2 — 5% overscan-safe inset at the 1920x1080 baseline. Nothing
     *  meaningful (text, controls, resting focus rings) crosses this line. */
    val OverscanH = 48.dp
    val OverscanV = 27.dp

    /** §4.6 — rows at the root; grids only inside a chosen scope. */
    val PosterWidth = 148.dp
    val PosterSpacing = 20.dp
    val RowSpacing = 28.dp

    /** §3.2 — the focused item is distinguished by scale AND ring AND lift.
     *  Colour alone is never sufficient at ten feet. */
    // Native Google TV grammar: 1.10 scale + a white hairline border +
    // a quiet lift. The earlier 3dp accent-coloured ring read as a chunky
    // custom indicator (owner 2026-08-28: "huge selection indicator").
    const val FocusScale = 1.10f
    val FocusRing = 2.5.dp
    val FocusElevation = 8.dp

    val NavRailWidth = 220.dp
    val NavRailCollapsed = 88.dp
}
