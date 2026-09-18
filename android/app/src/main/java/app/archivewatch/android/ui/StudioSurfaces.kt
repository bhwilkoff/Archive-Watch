package app.archivewatch.android.ui

// Watch Together Studio's surfaces over the player — ANDROID-DESIGN §9.3 and
// §9.4. There is no new screen here: §9.1 (and §5.1 before it) says the Studio
// is the player with overlays, never a parallel transport.

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import app.archivewatch.android.studio.StudioController
import app.archivewatch.android.studio.StudioHealth
import app.archivewatch.android.studio.StudioRights

private val Marquee = Color(0xFFFF5C35)

/**
 * §9.4 — health, ALWAYS on screen while live and outside `PlayerView`'s own
 * controls. Media3's controller auto-hides; health may not
 * (docs/WATCH-TOGETHER.md §4). It states the one current problem in words,
 * because a phone in a stand and a television across a room are both read at
 * a glance or not at all.
 */
@Composable
fun StudioReadout(health: StudioHealth, onOpenPanel: () -> Unit, onEnd: () -> Unit) {
    Column(
        Modifier
            .background(Color(0xA6000000), RoundedCornerShape(10.dp))
            .padding(horizontal = 12.dp, vertical = 9.dp),
    ) {
        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            // A red dot only when the show is actually going out — a green or
            // red light that means nothing is worse than none.
            Spacer(
                Modifier.size(9.dp).background(
                    if (health.showState == "LIVE") Color.Red else Color(0xFF8A8F98),
                    CircleShape,
                ),
            )
            Spacer(Modifier.width(8.dp))
            Text(health.showState, color = Color.White,
                 fontSize = 12.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.width(10.dp))
            Text("${health.encodedFramesPerSecond} fps", color = Color.White, fontSize = 12.sp)
            Spacer(Modifier.width(10.dp))
            Text(String.format("%.1f ms", health.averageRenderMillis),
                 color = Color(0xFFBBBBBB), fontSize = 12.sp)
            Spacer(Modifier.width(10.dp))
            TextButton(onClick = onOpenPanel) { Text("Controls", fontSize = 12.sp) }
            TextButton(onClick = onEnd) { Text("End", color = Marquee, fontSize = 12.sp) }
        }
        health.problem?.let {
            Text(it, color = Color(0xFFFFA726), fontSize = 11.sp,
                 modifier = Modifier.width(330.dp))
        }
    }
}

/**
 * §9.3 — the program panel as a Material bottom sheet, the native idiom of
 * the iOS medium-detent sheet (§8.2). The program stays visible behind it,
 * because changing what an audience sees without seeing it is a guess rather
 * than a control.
 *
 * Deliberately short: the film's transport belongs to `PlayerView` (§5.1), so
 * what lives here is the PROGRAM. Health is two lines rather than eight — the
 * readout above already carries the state and the problem, and a sheet that
 * cannot grow past its window is where the Apple panel learned that lesson.
 */
@OptIn(ExperimentalMaterial3Api::class)
@UnstableApi
@Composable
fun StudioPanel(health: StudioHealth, onDismiss: () -> Unit, onEnd: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(20.dp)) {
            Text("Studio", fontWeight = FontWeight.Bold, fontSize = 20.sp)
            Spacer(Modifier.size(12.dp))

            Text("Program", fontWeight = FontWeight.SemiBold)
            Text(String.format("%.1f ms per frame · %d fps encoded",
                               health.averageRenderMillis, health.encodedFramesPerSecond))
            Text("${health.publisher.videoFramesDropped} dropped · " +
                 "film ${health.filmFramesPerSecond} fps")
            health.problem?.let {
                Spacer(Modifier.size(6.dp))
                Text(it, color = Color(0xFFFFA726))
            }

            Spacer(Modifier.size(16.dp))
            HorizontalDivider()
            Spacer(Modifier.size(16.dp))

            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
            ) {
                Column {
                    Text("Show you in the corner", fontWeight = FontWeight.Medium)
                    Text("Needs a camera — a television has none.",
                         fontSize = 12.sp, color = Color(0xFF8A8F98))
                }
                Switch(
                    checked = StudioController.showsCamera,
                    onCheckedChange = { StudioController.showsCamera = it },
                )
            }

            Spacer(Modifier.size(16.dp))
            HorizontalDivider()
            Spacer(Modifier.size(16.dp))
            // What the gate cannot protect a host from (§3.4a) — the same
            // sentence every platform shows, kept identical by
            // tools/test_studio_rights_parity.py.
            Text(StudioRights.hostWarning, fontSize = 12.sp, color = Color(0xFFFFA726))

            Spacer(Modifier.size(20.dp))
            Button(onClick = onEnd) { Text("End the broadcast") }
            Spacer(Modifier.size(12.dp))
        }
    }
}
