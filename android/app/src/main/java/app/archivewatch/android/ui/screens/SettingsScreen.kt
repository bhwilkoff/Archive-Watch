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
                        container.catalog.applyFilters(!show)
                    }
                },
            )
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
                SectionLabel("Sync")
                val activity = androidx.compose.ui.platform.LocalContext.current
                    as? android.app.Activity
                Text(
                    if (app.archivewatch.android.sync.DriveSync.isSignedIn)
                        "Syncing your watch history and library through your Google Drive."
                    else "Sign in with Google to sync your watch history and library across devices.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                androidx.compose.material3.TextButton(onClick = {
                    val act = activity ?: return@TextButton
                    if (app.archivewatch.android.sync.DriveSync.isSignedIn) {
                        app.archivewatch.android.sync.DriveSync.signOut()
                    } else {
                        app.archivewatch.android.sync.DriveSync.signIn(act, container.userState) {}
                    }
                }) {
                    Text(if (app.archivewatch.android.sync.DriveSync.isSignedIn)
                        "Sign out" else "Sign in with Google")
                }
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
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
