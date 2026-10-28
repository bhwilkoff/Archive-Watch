package app.archivewatch.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.SaveableStateHolder
import androidx.compose.runtime.saveable.rememberSaveableStateHolder

/**
 * Saved state per back-stack entry, held by the root so it outlives the moment
 * the stack is empty. A popped entry's state is dropped, so a later push at the
 * same depth starts fresh.
 */
class RouteStates(val holder: SaveableStateHolder) {
    internal val provided = HashMap<Int, String>()

    internal fun prune(depth: Int) {
        provided.keys.filter { it > depth }.forEach { d -> provided.remove(d)?.let { holder.removeState(it) } }
    }
}

@Composable
fun rememberRouteStates(nav: Nav): RouteStates {
    val holder = rememberSaveableStateHolder()
    val states = remember(holder) { RouteStates(holder) }
    LaunchedEffect(nav.stack.size) { states.prune(nav.stack.size) }
    return states
}

/**
 * The top route, composed under its own identity and its own saved state.
 *
 * `key`: Detail -> More Like This -> Detail is the same composable called with
 * a new id, so without it the second page kept the first page's scroll and
 * remembered state. The holder: Back to a Detail (or a grid) returns to where
 * the viewer left it instead of the top, as the tabs already do.
 */
@Composable
fun RouteEntry(nav: Nav, states: RouteStates, route: Route, content: @Composable () -> Unit) {
    val depth = nav.stack.size
    val entryKey = "route|$depth|${route.hashCode()}"
    LaunchedEffect(depth, entryKey) {
        states.provided[depth]?.takeIf { it != entryKey }?.let { states.holder.removeState(it) }
        states.provided[depth] = entryKey
    }
    key(entryKey) { states.holder.SaveableStateProvider(entryKey) { content() } }
}
