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
import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import app.archivewatch.android.studio.StudioRights

@Composable
fun StudioGoLiveDialog(
    filmTitle: String,
    onGoLive: () -> Unit,
    onDismiss: () -> Unit,
) {
    var signedIn by remember { mutableStateOf(false) }

    // THE CAMERA AND THE MICROPHONE ARE ASKED FOR HERE, and nowhere else.
    //
    // This is the surface where a host has chosen to broadcast, which is the
    // only moment the request means anything — the same rule tvOS-DESIGN
    // §10.2b applies to sign-in: never a Settings row, never a pre-flight the
    // viewer must clear before they have chosen to broadcast anything.
    //
    // NEITHER IS REQUIRED. §8.8's rule is that an absent camera is normal, so
    // a refusal does not disable Go live — the show carries the film, and
    // `StudioCamera.problem` / `StudioMicAudio.problem` put a sentence on the
    // readout rather than leaving the host to wonder. The app had never asked
    // for a runtime permission before this (it declared only INTERNET), which
    // is why Android could broadcast a film and never the host.
    val context = LocalContext.current
    fun granted(p: String) =
        ContextCompat.checkSelfPermission(context, p) == PackageManager.PERMISSION_GRANTED
    fun hostGranted() = granted(Manifest.permission.CAMERA) && granted(Manifest.permission.RECORD_AUDIO)
    var hostOk by remember { mutableStateOf(hostGranted()) }
    // Set when the system has answered no. Android stops showing the prompt
    // after a second refusal and the launcher returns at once, so without
    // this the button did nothing and nothing said why.
    var hostRefused by remember { mutableStateOf(false) }
    val askHost = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()) {
        hostOk = hostGranted()
        hostRefused = !hostOk
    }
    // Back from Settings: read the grant again.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val obs = LifecycleEventObserver { _, e ->
            if (e == Lifecycle.Event.ON_RESUME) {
                hostOk = hostGranted()
                if (hostOk) hostRefused = false
            }
        }
        lifecycle.addObserver(obs)
        onDispose { lifecycle.removeObserver(obs) }
    }

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
                        "Sign in above to go live.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                if (!hostOk && hostRefused) {
                    val off = listOfNotNull(
                        "camera".takeIf { !granted(Manifest.permission.CAMERA) },
                        "microphone".takeIf { !granted(Manifest.permission.RECORD_AUDIO) },
                    ).joinToString(" and ")
                    Text(
                        "Archive Watch is not allowed to use the $off. Turn it on in Settings.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    TextButton(onClick = {
                        context.startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                   Uri.fromParts("package", context.packageName, null))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }) { Text("Open Settings") }
                } else if (!hostOk) {
                    TextButton(onClick = {
                        askHost.launch(arrayOf(Manifest.permission.CAMERA,
                                               Manifest.permission.RECORD_AUDIO))
                    }) { Text("Allow the camera and microphone") }
                    // A refusal, not an option (owner, 2026-09-24): the film
                    // alone is already on archive.org, so a broadcast without
                    // the host adds nothing (Decision 132, at go-live).
                    Text(
                        "Going live needs your camera and microphone — you are the show.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(enabled = signedIn && hostOk, onClick = onGoLive) { Text("Go live") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Not now") }
        },
    )
}
