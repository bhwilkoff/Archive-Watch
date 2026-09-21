package app.archivewatch.android.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.studio.StudioRoom
import app.archivewatch.android.studio.StudioSyncClient
import app.archivewatch.android.studio.StudioSyncFollower
import kotlinx.coroutines.launch

/**
 * JOIN A ROOM on the phone — SHAREPLAY §11.9.
 *
 * **Why the Library app bar and not a sixth tab.** Android's bottom bar
 * already carries five, exactly as iOS's does, and `LibraryScreen` records the
 * measurement that made its own tab row scrollable — five labels at a phone
 * width wrapped "Playlists" onto two lines on the owner's Pixel. A sixth
 * top-level destination would fight a constraint somebody already measured.
 *
 * **Not Settings** (§11.9): joining is a thing you DO, not a way the app
 * behaves.
 *
 * **And it needs no camera** (§11.10). Decision 132 gates HOSTING on a camera
 * and a microphone — a joiner contributes nothing to the programme, so the
 * entry is NOT behind `canHostWatchTogether()`.
 */
@Composable
fun JoinRoomDialog(onDismiss: () -> Unit, onJoined: (code: String, filmID: String) -> Unit) {
    var typed by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Join a room") },
        text = {
            Column {
                Text(
                    "Ask the host to read out their four-character code. You do not " +
                        "need a camera or a microphone — you are watching along, and the " +
                        "conversation is on the call you are already on.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Spacer(Modifier.size(16.dp))
                OutlinedTextField(
                    value = typed,
                    onValueChange = {
                        // Uppercased as typed and stopped at the code's length,
                        // so a stray keystroke cannot invalidate a code the
                        // host just read out.
                        typed = it.uppercase().filter { c -> !c.isWhitespace() && c != '-' }
                            .take(StudioRoom.CODE_LENGTH)
                        problem = null
                    },
                    singleLine = true,
                    textStyle = TextStyle(
                        fontSize = 34.sp, fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace, textAlign = TextAlign.Center,
                    ),
                    // A code is Base32, so autocorrect would cheerfully rewrite
                    // four characters into a word.
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Characters,
                        autoCorrectEnabled = false,
                    ),
                )
                problem?.let {
                    Spacer(Modifier.size(10.dp))
                    Text(it, style = MaterialTheme.typography.bodySmall,
                         color = MaterialTheme.colorScheme.error)
                }
                if (working) { Spacer(Modifier.size(10.dp)); CircularProgressIndicator() }
            }
        },
        confirmButton = {
            TextButton(
                enabled = StudioRoom.normalize(typed) != null && !working,
                onClick = {
                    val code = StudioRoom.normalize(typed) ?: return@TextButton
                    working = true
                    scope.launch {
                        val client = StudioSyncClient()
                        try {
                            val state = client.join(code)
                            client.leave()
                            working = false
                            onJoined(code, state.filmID)
                        } catch (e: Exception) {
                            working = false
                            problem = StudioSyncFollower.sentence(e)
                        }
                    }
                },
            ) { Text("Join") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
