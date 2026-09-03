package app.archivewatch.android.ui.screens

import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TextButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import android.net.Uri
import app.archivewatch.android.BuildConfig
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.tv.LocalIsTelevision
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

private const val DONATE_URL = "https://archive.org/donate"

private const val TMDB_NOTICE =
    "This product uses the TMDB API but is not endorsed or certified by TMDB."

private const val SOURCES =
    "Films and video stream directly from the Internet Archive (archive.org). " +
        "Posters, cast, and synopses are enriched from The Movie Database (TMDb), " +
        "TheTVDB, TVmaze, Wikidata, Wikimedia Commons, and the Library of Congress."

/** Settings — mature filter (Decision 012), attribution (007), donate (010). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(container: AppContainer, nav: Nav) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val hideAdult by container.settings.hideAdultContent.collectAsState(initial = true)
    val hiddenCategories by container.settings.hiddenCategories.collectAsState(initial = emptySet())
    val autoplay by container.settings.autoplayNext.collectAsState(initial = false)
    val hideWatched by container.settings.hideWatchedOnHome.collectAsState(initial = false)
    val isTv = LocalIsTelevision.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
        ) {
            SectionLabel("Content")
            ToggleRow(
                title = "Show mature collections",
                subtitle = "Hidden by default. Applies everywhere.",
                checked = !hideAdult,
                onCheckedChange = { show ->
                    scope.launch {
                        container.settings.setHideAdultContent(!show)
                        container.catalog.applyFilters(
                            !show,
                            container.settings.hiddenCategories.first(),
                        )
                    }
                },
            )
            // tvOS parity: per-category visibility. Hiding a category removes
            // it from every surface (the filter is applied at the DB layer).
            SectionLabel("Show categories")
            listOf(
                "Feature films" to "feature-film",
                "Short films" to "short-film",
                "Silent era" to "silent-film",
                "Animation" to "animation",
                "Newsreels" to "newsreel",
                "Documentaries" to "documentary",
                "Ephemeral films" to "ephemeral",
                "Commercials" to "commercial",
            ).forEach { (label, type) ->
                ToggleRow(
                    title = label,
                    subtitle = null,
                    checked = type !in hiddenCategories,
                    onCheckedChange = { show ->
                        scope.launch {
                            container.settings.setCategoryHidden(type, !show)
                            container.catalog.applyFilters(
                                container.settings.hideAdultContent.first(),
                                container.settings.hiddenCategories.first(),
                            )
                        }
                    },
                )
            }

            ToggleRow(
                title = "Hide watched titles on Home",
                subtitle = "Completed titles disappear from Home shelves.",
                checked = hideWatched,
                onCheckedChange = { scope.launch { container.settings.setHideWatchedOnHome(it) } },
            )
            ToggleRow(
                title = "Autoplay next",
                subtitle = "Keep playing when an episode or film ends.",
                checked = autoplay,
                onCheckedChange = { value ->
                    scope.launch { container.settings.setAutoplayNext(value) }
                },
            )

            HorizontalDivider(Modifier.padding(vertical = 16.dp))

            SectionLabel("Subtitles")
            OpenSubtitlesSection(container)

            // Android's prong is discoverability, not engineering. There is no
            // public API to transcribe a FILE — createOnDeviceSpeechRecognizer
            // is a microphone pipeline — but the system's Live Caption already
            // captions whatever this app plays, on-device, with Google's model,
            // for any film we have no subtitle track for. Most people have never
            // been told it exists, so the app says so and opens the settings
            // page. ACTION_CAPTIONING_SETTINGS is the public, stable entry
            // point; Live Caption itself has no documented deep link, and it is
            // toggled from the volume rocker, so that is spelled out.
            Text(
                "Films without a subtitle track can still be captioned by Android itself. " +
                    "Live Caption transcribes anything playing on this device, offline, " +
                    "and works on every title.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "Turn it on from Caption preferences, or press a volume key while a film " +
                    "is playing and tap the Live Caption button.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "Open caption settings",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        // Fall back to Accessibility if a device (or a TV build)
                        // ships no captioning activity — an unresolved intent
                        // would otherwise crash rather than degrade.
                        runCatching {
                            context.startActivity(
                                Intent(android.provider.Settings.ACTION_CAPTIONING_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                            )
                        }.onFailure {
                            runCatching {
                                context.startActivity(
                                    Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                                )
                            }
                        }
                    }
                    .padding(vertical = 12.dp),
            )

            HorizontalDivider(Modifier.padding(vertical = 16.dp))

            // Cross-device sync (Decision 028): user's own Google Drive
            // appDataFolder, sharing awsync.json with the web viewer. HIDDEN
            // until the OAuth client is configured (BuildConfig field —
            // docs/google-oauth-setup.md); absent entirely on the amazon
            // flavor (DriveSync twin, same pattern as CastSupport).
            if (app.archivewatch.android.sync.DriveSync.IS_SUPPORTED &&
                app.archivewatch.android.sync.DriveSync.isConfigured
            ) {
                SyncSection()
                HorizontalDivider(Modifier.padding(vertical = 16.dp))
            }

            SectionLabel("About")
            Text(
                TMDB_NOTICE,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(12.dp))
            Text(
                SOURCES,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            HorizontalDivider(Modifier.padding(vertical = 16.dp))

            // Donate (Decision 010). The link is REACHABLE on TV — verified on
            // the emulator that D-pad focus lands on it, since Modifier
            // .clickable carries focusability. The problem is what happens
            // next: Android TV ships no browser, so ACTION_VIEW resolves to
            // `frameworkpackagestubs.Stubs$BrowserStub` (verified with
            // `pm resolve-activity`) — a stub whose whole job is to tell the
            // user nothing can open this. And card details cannot be typed with
            // a remote regardless.
            //
            // So TV shows the address to read and type on a phone, matching the
            // tvOS app; only touch devices get a live link.
            if (isTv) {
                Text(
                    "Support the Internet Archive",
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                )
                Text(
                    DONATE_URL,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
                )
            } else {
                Text(
                    "Donate to the Internet Archive",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            // Most phones resolve this fine, but a device with
                            // no handler at all throws ActivityNotFound — a
                            // donate link must never take the app down.
                            runCatching {
                                context.startActivity(
                                    Intent(Intent.ACTION_VIEW, Uri.parse(DONATE_URL)),
                                )
                            }
                        }
                        .padding(vertical = 12.dp),
                )
            }

            HorizontalDivider(Modifier.padding(vertical = 16.dp))

            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                Text("Version", style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.weight(1f))
                Text(
                    BuildConfig.VERSION_NAME,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(32.dp))
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(vertical = 8.dp),
    )
}

@Composable
private fun ToggleRow(
    title: String,
    subtitle: String?,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            subtitle?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

/**
 * The viewer's OpenSubtitles account (iOS SubtitleAccountSection parity).
 * Username + password only — the API key ships in the build, and the
 * download allowance follows THEIR account, so the number shown is the
 * API's own answer, never our guess.
 */
@Composable
private fun OpenSubtitlesSection(container: AppContainer) {
    val scope = rememberCoroutineScope()
    var connected by remember { mutableStateOf(container.subtitleAccount.isConnected) }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    if (!app.archivewatch.android.data.OpenSubtitlesClient.isAvailable) return

    if (connected) {
        Text(
            "OpenSubtitles: " + (container.subtitleAccount.username ?: ""),
            style = MaterialTheme.typography.bodyLarge,
        )
        val allowed = container.subtitleAccount.quotaAllowed
        if (allowed > 0) {
            Text(
                "Downloads today: " +
                    (allowed - container.subtitleAccount.quotaRemaining) + " of " + allowed + " used",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        TextButton(onClick = {
            container.subtitleAccount.disconnect(); connected = false
        }) { Text("Disconnect OpenSubtitles") }
    } else {
        Text(
            "Connect a free OpenSubtitles account to find subtitles for films " +
                "that don't have them. Your daily allowance is your own.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedTextField(
            value = username, onValueChange = { username = it },
            label = { Text("OpenSubtitles username (not your email)") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        )
        OutlinedTextField(
            value = password, onValueChange = { password = it },
            label = { Text("Password") },
            singleLine = true,
            visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(
                enabled = username.isNotBlank() && password.isNotBlank() && !working,
                onClick = {
                    working = true; error = null
                    scope.launch {
                        try {
                            container.subtitleAccount.connect(username, password)
                            connected = true; password = ""
                        } catch (e: Exception) {
                            error = e.message
                        }
                        working = false
                    }
                },
            ) { Text(if (working) "Connecting…" else "Connect") }
            TextButton(onClick = {
                // create-account door, in the browser
            }) { }
        }
        error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall,
                 color = MaterialTheme.colorScheme.error)
        }
    }
    HorizontalDivider(Modifier.padding(vertical = 12.dp))
}
/**
 * Sign in with Google → Drive App Data sync (Decision 028; the
 * per-ecosystem-sync-islands rules: sign-in gates ONLY sync, and status is
 * never silent — account, last sync, last error and a Sync now button).
 * Shared by phone and TV: on Google TV the same Play-services consent UI
 * appears, TV-styled.
 */
@Composable
private fun SyncSection() {
    val sync = app.archivewatch.android.sync.DriveSync
    val status by sync.status.collectAsState()
    val activity = androidx.compose.ui.platform.LocalContext.current as? android.app.Activity
    val consent = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.StartIntentSenderForResult(),
    ) { result ->
        activity?.let { sync.onConsentResult(it, result.data) }
    }

    SectionLabel("Sync")
    Text(
        if (status.signedIn)
            "Your favorites, playlists, channels and watch history sync through your own Google Drive" +
                (status.account?.let { " ($it)." } ?: ".")
        else "Sign in with Google to sync your favorites, playlists, channels and watch history " +
            "across your Android devices and archivewatch.org. Nothing leaves your own Google Drive.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    if (status.signedIn) {
        val stamp = status.lastSyncAt.takeIf { it > 0 }?.let {
            java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.SHORT, java.text.DateFormat.SHORT)
                .format(java.util.Date(it))
        }
        Text(
            when {
                status.syncing -> "Syncing…"
                status.lastError != null -> "Last sync failed: " + status.lastError
                stamp != null -> "Last synced $stamp"
                else -> "Not synced yet"
            },
            style = MaterialTheme.typography.bodySmall,
            color = if (status.lastError != null) MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 4.dp),
        )
    } else if (status.lastError != null) {
        Text(
            status.lastError!!,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
    androidx.compose.foundation.layout.Row {
        androidx.compose.material3.TextButton(onClick = {
            val act = activity ?: return@TextButton
            if (status.signedIn) sync.signOut()
            else sync.signIn(act) { sender ->
                consent.launch(androidx.activity.result.IntentSenderRequest.Builder(sender).build())
            }
        }) {
            Text(if (status.signedIn) "Sign out" else "Sign in with Google")
        }
        if (status.signedIn) {
            androidx.compose.material3.TextButton(
                onClick = { sync.syncNow() },
                enabled = !status.syncing,
            ) { Text("Sync now") }
        }
    }
}
