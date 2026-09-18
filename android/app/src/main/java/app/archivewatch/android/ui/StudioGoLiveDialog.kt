package app.archivewatch.android.ui

// The moment before a broadcast (ANDROID-DESIGN §9.11, WATCH-TOGETHER §3.4a).
//
// Android's "Watch Together…" used to arm the Studio and push straight to the
// player: no sign-in, no destination, no warning — the same shape tvOS had
// before Rule 8.8a, and for the same reason (the surface was never written).
//
// This is the Android counterpart, and deliberately NOT a port of the tvOS
// two-column screen: §9.3's idiom here is a Material dialog, and Android's
// title needs no editing step because the film's own record is what the host
// would type anyway. What it must carry is what tvOS carries — the film, where
// it goes, §3.4a's warning, and a sign-in — because those are the things a host
// cannot discover afterwards.

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.archivewatch.android.studio.StudioRights

@Composable
fun StudioGoLiveDialog(
    filmTitle: String,
    onGoLive: () -> Unit,
    onDismiss: () -> Unit,
) {
    var signedIn by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Go live with the world") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(filmTitle, style = MaterialTheme.typography.titleMedium)

                // §9.11 — the QR and the code, together. The token lands here.
                StudioSignIn(onSignedInChange = { signedIn = it })

                // §3.4a, every time, on the surface where Go live is pressed —
                // the same string every platform shows, guarded sentence for
                // sentence by tools/test_studio_rights_parity.py.
                Text(
                    StudioRights.hostWarning,
                    style = MaterialTheme.typography.bodySmall,
                )
                if (!signedIn) {
                    Text(
                        "Sign in above to go live. Nothing is broadcast until you press Go live.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(enabled = signedIn, onClick = onGoLive) { Text("Go live") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Not now") }
        },
    )
}
