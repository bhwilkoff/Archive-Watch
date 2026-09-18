package app.archivewatch.android.ui

// Signing in to a streaming platform, on screen (docs/ANDROID-DESIGN.md §9.11).
//
// A QR code AND the code, shown together, because Android ships on televisions
// and a television has no keyboard. The host authorises on their phone; the
// token lands HERE. Twitch only — §9.11 says why YouTube is named rather than
// offered.

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.studio.StudioPlatformAuth
import app.archivewatch.android.studio.StudioTokenStore
import app.archivewatch.android.ui.tv.qrBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** "https://www.twitch.tv/activate?device-code=X" -> "twitch.tv/activate". */
internal fun shortHost(uri: String): String = runCatching {
    val u = java.net.URI(uri)
    (u.host ?: return uri).removePrefix("www.") + (u.path ?: "")
}.getOrDefault(uri)

@Composable
fun StudioSignIn(
    modifier: Modifier = Modifier,
    onSignedInChange: (Boolean) -> Unit = {},
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var signedIn by remember { mutableStateOf(StudioTokenStore.isSignedIn(context, StudioPlatformAuth.TWITCH)) }
    var account by remember { mutableStateOf<String?>(null) }
    var pending by remember { mutableStateOf<StudioPlatformAuth.Pending?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    // Held so Cancel can cancel the WORK, not just the picture of it: the poll
    // runs for the life of the code — up to 30 minutes at one request every 5
    // seconds — so hiding the code without cancelling leaves hundreds of
    // requests running against Twitch (the tvOS lesson, WATCH-TOGETHER §9.sss).
    var job by remember { mutableStateOf<Job?>(null) }

    LaunchedEffect(signedIn) {
        onSignedInChange(signedIn)
        if (signedIn && account == null) {
            account = withContext(Dispatchers.IO) {
                runCatching { StudioPlatformAuth.account(context).login }.getOrNull()
            }
        }
    }

    val configProblem = StudioPlatformAuth.configurationProblem()

    Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        when {
            configProblem != null ->
                Text(configProblem, style = MaterialTheme.typography.bodyMedium)

            signedIn -> Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    account?.let { "Twitch — $it" } ?: "Signed in to Twitch",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Medium,
                )
                Spacer(Modifier.width(16.dp))
                TextButton(onClick = {
                    StudioTokenStore.clear(context, StudioPlatformAuth.TWITCH)
                    account = null
                    signedIn = false
                }) { Text("Sign out") }
            }

            pending != null -> {
                val p = pending!!
                Row(verticalAlignment = Alignment.Top) {
                    // The QR carries Twitch's verification_uri, which ALREADY
                    // embeds the user code (§9.11) — scanning reaches a
                    // pre-filled page rather than a form.
                    val bmp: Bitmap? = remember(p.verificationUri) { qrBitmap(p.verificationUri, 320) }
                    if (bmp != null) {
                        Image(
                            bitmap = bmp.asImageBitmap(),
                            contentDescription = "Scan to sign in to Twitch",
                            modifier = Modifier
                                .size(200.dp)
                                .background(Color.White, RoundedCornerShape(10.dp))
                                .padding(8.dp),
                        )
                        Spacer(Modifier.width(24.dp))
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        // Short host+path, never the full URI — the full string
                        // reads as noise directly above the code it contains.
                        Text(
                            "Scan the code, or open ${shortHost(p.verificationUri)} " +
                                "on your phone and enter:",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        Text(
                            p.userCode,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold,
                            fontSize = 40.sp,
                        )
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(18.dp))
                            Spacer(Modifier.width(10.dp))
                            Text(
                                "Waiting for you to confirm on Twitch…",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        TextButton(onClick = {
                            job?.cancel(); job = null; pending = null
                        }) { Text("Cancel") }
                    }
                }
            }

            else -> Button(
                enabled = !working,
                onClick = {
                    problem = null
                    working = true
                    job = scope.launch {
                        try {
                            // Both calls BLOCK on the network, so neither may
                            // run on the main dispatcher — Decision 130's
                            // Android lesson, which a JVM test cannot catch.
                            val p = withContext(Dispatchers.IO) { StudioPlatformAuth.begin() }
                            pending = p
                            working = false
                            withContext(Dispatchers.IO) { StudioPlatformAuth.poll(context, p) }
                            pending = null
                            signedIn = true
                        } catch (c: kotlinx.coroutines.CancellationException) {
                            pending = null
                            throw c
                        } catch (t: Throwable) {
                            pending = null
                            problem = t.message ?: "Twitch would not start a sign-in."
                        } finally {
                            working = false
                        }
                    }
                },
            ) { Text("Sign in to Twitch") }
        }

        problem?.let {
            Text(it, color = MaterialTheme.colorScheme.error,
                 style = MaterialTheme.typography.bodySmall)
        }
    }
}
