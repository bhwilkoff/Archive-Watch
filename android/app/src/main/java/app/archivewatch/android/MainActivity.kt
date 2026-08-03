package app.archivewatch.android

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import app.archivewatch.android.app.ArchiveWatchApplication
import app.archivewatch.android.ui.AppRoot
import app.archivewatch.android.ui.DeepLinks
import app.archivewatch.android.ui.PlaybackPresence
import app.archivewatch.android.ui.theme.ArchiveWatchTheme
import app.archivewatch.android.ui.tv.LocalIsTelevision
import app.archivewatch.android.ui.tv.TvAppRoot
import app.archivewatch.android.ui.tv.isTelevision

/** Single Activity — Compose-only. */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleDeepLink(intent)

        val container = (application as ArchiveWatchApplication).container

        // TV is a runtime branch off ONE activity, never a second entry point
        // or a build flavor (docs/TV-DESIGN.md §6.5, Decision 047). Resolved
        // once here so no composable has to ask again.
        val isTv = isTelevision()

        setContent {
            ArchiveWatchTheme {
                CompositionLocalProvider(LocalIsTelevision provides isTv) {
                    if (isTv) TvAppRoot(container) else AppRoot(container)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    /** Leaving the app (Home / recents) mid-playback drops the player into a
        Picture-in-Picture window, sized to the real video aspect. */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!PlaybackPresence.active.value) return
        // TV-NP: on a TV, leaving the app must PAUSE the video, not float it in
        // a PiP window (the player's lifecycle observer does the pausing).
        // docs/TV-DESIGN.md §5.4.
        if (isTelevision()) return
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
        val w = PlaybackPresence.aspectWidth
        val h = PlaybackPresence.aspectHeight
        // Android rejects PiP aspect ratios outside [1:2.39 .. 2.39:1]; fall back
        // to 16:9 for anything out of range (or an unknown video size).
        val ratio = if (h > 0) w.toFloat() / h else 0f
        val ar = if (ratio in 0.42f..2.39f) Rational(w, h) else Rational(16, 9)
        runCatching {
            enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(ar).build())
        }
    }

    /** archivewatch://item/{id} (same scheme as tvOS/iOS) and verified App
        Links from https://archivewatch.org/item/{id} + /series/{slug} → the
        matching surface. */
    private fun handleDeepLink(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme == "archivewatch" && uri.host == "item") {
            uri.lastPathSegment?.let { DeepLinks.pendingItem.value = it }
            return
        }
        if (uri.scheme == "archivewatch" && uri.host in setOf("surprise", "channels")) {
            DeepLinks.pendingAction.value = uri.host
            return
        }
        if (uri.host == "archivewatch.org") {
            val segs = uri.pathSegments
            if (segs.size >= 2) {
                when (segs[0]) {
                    "item" -> DeepLinks.pendingItem.value = segs[1]
                    // The series card id in the catalog is "series:<slug>".
                    "series" -> DeepLinks.pendingItem.value = "series:${segs[1]}"
                }
            }
        }
    }
}
