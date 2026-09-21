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
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.RadioButton
import androidx.compose.foundation.clickable
import app.archivewatch.android.studio.StudioCard
import app.archivewatch.android.studio.StudioLayout
import androidx.compose.material3.Slider
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
import app.archivewatch.android.studio.MixLevel
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

            // WHERE YOU GO IN THE PICTURE — the same five placements every
            // other platform offers, in the same words (`StudioLayout.label`
            // is shared on Apple and ported here verbatim). Android had a
            // SWITCH, which could express only two of the five, so three
            // placements existed in the engine and nowhere a host could reach
            // them. Owner 2026-09-20: "The goal is parity, where it makes
            // sense." A radio list rather than a dropdown because there are
            // five and they are a choice, not a setting to hunt for.
            Text("Where you go", fontWeight = FontWeight.SemiBold)
            Text("A camera is needed for all but the first — a television has none.",
                 fontSize = 12.sp, color = Color(0xFF8A8F98))
            Spacer(Modifier.size(8.dp))
            for (option in StudioLayout.entries) {
                Row(
                    Modifier.fillMaxWidth().clickable { StudioController.layout = option },
                    verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = StudioController.layout == option,
                        onClick = { StudioController.layout = option },
                    )
                    Text(option.label, fontSize = 14.sp)
                }
            }

            Spacer(Modifier.size(16.dp))
            HorizontalDivider()
            Spacer(Modifier.size(16.dp))

            // CARDS — a full-frame graphic that REPLACES the programme, for the
            // moments a broadcast has and a film does not: before it starts,
            // in the middle, at the end. They existed on macOS and iOS only.
            Text("Show a card", fontWeight = FontWeight.SemiBold)
            Text("Replaces the picture for your audience.",
                 fontSize = 12.sp, color = Color(0xFF8A8F98))
            Spacer(Modifier.size(8.dp))
            val cards: List<Pair<String, StudioCard?>> = listOf(
                "None" to null,
                "Starting soon" to StudioCard.StartingSoon(60),
                "Intermission" to StudioCard.Intermission,
                "Thanks for watching" to StudioCard.Ending,
            )
            for ((label, value) in cards) {
                val selected = StudioController.card?.javaClass == value?.javaClass
                Row(
                    Modifier.fillMaxWidth().clickable { StudioController.card = value },
                    verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                ) {
                    RadioButton(selected = selected,
                                onClick = { StudioController.card = value })
                    Text(label, fontSize = 14.sp)
                }
            }

            Spacer(Modifier.size(16.dp))
            HorizontalDivider()
            Spacer(Modifier.size(16.dp))

            // SOUND — the same 0-10 scale as every other platform (Rule
            // 8.8c, iOS-DESIGN §8.8c, macOS-DESIGN §B13h). Android had NO
            // mix controls at all until 2026-09-20: no faders, no duck, and
            // no microphone for them to govern (§9.qqqqq).
            //
            // `Slider` is the native control here, as it is on iOS and
            // macOS — it is `@available(tvOS, unavailable)`, which is the one
            // reason the television draws its own. Only the SCALE is ours.
            Text("Sound", fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.size(4.dp))
            StudioFader("Film", StudioController.filmLevel,
                        StudioController.programLevel) { StudioController.filmLevel = it }
            if (StudioController.hasVoice) {
                StudioFader("Your microphone", StudioController.micLevel,
                            StudioController.voiceLevel) { StudioController.micLevel = it }
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("Duck the film under my voice", fontWeight = FontWeight.Medium)
                        // AUTO-DUCK IS A CONTROL, NOT A SENTENCE. Without the
                        // switch a host who sets Film to 9 and then speaks
                        // hears it drop 12 dB anyway and reasonably concludes
                        // the fader is broken. Manual has to mean manual.
                        Text(
                            if (!StudioController.duckEnabled)
                                "The film stays where you set it. 8 is the level it already has."
                            else if (StudioController.ducking)
                                "The film is ducking under your voice."
                            else "The film drops 12 dB automatically while you are talking.",
                            fontSize = 12.sp, color = Color(0xFF8A8F98),
                        )
                    }
                    Switch(
                        checked = StudioController.duckEnabled,
                        onCheckedChange = { StudioController.duckEnabled = it },
                    )
                }
            } else {
                Text("No microphone in this show — your audience hears the film only.",
                     fontSize = 12.sp, color = Color(0xFF8A8F98))
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

/**
 * One channel: a name, the level a host can say out loud, and a meter.
 *
 * The meter reads on the FADER's own scale rather than linearly. A linear
 * 0-1 meter draws 2% for speech at RMS 0.02 — which Apple measured from a
 * host talking beside the phone — and that is how a working microphone reads
 * as a broken one.
 */
@Composable
private fun StudioFader(
    label: String,
    level: Double,
    rms: Float,
    onLevel: (Double) -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(label, fontWeight = FontWeight.Medium)
            Text(MixLevel.text(level), fontWeight = FontWeight.Medium)
        }
        Slider(
            value = level.toFloat(),
            onValueChange = { onLevel(it.toDouble()) },
            valueRange = 0f..MixLevel.MAXIMUM.toFloat(),
        )
        LinearProgressIndicator(
            progress = { MixLevel.meterFraction(rms).toFloat() },
            modifier = Modifier.fillMaxWidth(),
        )
    }
}
