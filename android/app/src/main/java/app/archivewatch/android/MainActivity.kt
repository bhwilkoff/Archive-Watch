package app.archivewatch.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import app.archivewatch.android.app.ArchiveWatchApplication
import app.archivewatch.android.ui.AppRoot
import app.archivewatch.android.ui.DeepLinks
import app.archivewatch.android.ui.theme.ArchiveWatchTheme

/** Single Activity — Compose-only. */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleDeepLink(intent)

        val container = (application as ArchiveWatchApplication).container
        setContent {
            ArchiveWatchTheme {
                AppRoot(container)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
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
