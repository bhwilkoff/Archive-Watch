package app.archivewatch.android

import android.app.PictureInPictureParams
import kotlinx.coroutines.launch
import androidx.lifecycle.lifecycleScope
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
import app.archivewatch.android.cast.CastSupport
import app.archivewatch.android.ui.AppRoot
import app.archivewatch.android.ui.DeepLinks
import app.archivewatch.android.ui.PlaybackPresence
import app.archivewatch.android.ui.theme.ArchiveWatchTheme
import app.archivewatch.android.ui.tv.LocalIsTelevision
import app.archivewatch.android.ui.tv.TvAppRoot
import app.archivewatch.android.ui.tv.isTelevision
import app.archivewatch.android.studio.StudioPlatformAuth

/** Single Activity — Compose-only. */
// FragmentActivity (a ComponentActivity) because the Cast button's chooser is a
// DialogFragment; under a bare ComponentActivity every tap on it crashed.
class MainActivity : androidx.fragment.app.FragmentActivity() {

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

        // Cast discovery has to be running BEFORE the player opens or the
        // route button has nothing to show. No-ops on the amazon flavor (no
        // GMS) and on any device with Play Services missing or disabled.
        // Skipped on TV: a television is a Cast receiver, not a sender.
        if (!isTv) CastSupport.initialize(applicationContext)
        if (!isTv) lifecycleScope.launch { app.archivewatch.android.widgets.publishWidgetPreviews(applicationContext) }

        // Android 12+: the system enters PiP itself as the viewer swipes home,
        // animating from the video — onUserLeaveHint is too late for that.
        if (!isTv && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
            lifecycleScope.launch {
                kotlinx.coroutines.flow.combine(
                    PlaybackPresence.active, PlaybackPresence.aspect, PlaybackPresence.viewBounds,
                ) { a, _, v -> a to v }
                    .collect { (playing, view) ->
                        runCatching {
                            val b = PictureInPictureParams.Builder()
                                .setAspectRatio(pipAspect())
                                .setAutoEnterEnabled(playing)
                            filmRect(view)?.let { b.setSourceRectHint(it) }
                            setPictureInPictureParams(b.build())
                        }
                    }
            }
        }

        setContent {
            ArchiveWatchTheme {
                CompositionLocalProvider(LocalIsTelevision provides isTv) {
                    if (isTv) TvAppRoot(container) else AppRoot(container)
                }
            }
        }
    }

    @Suppress("DEPRECATION") // writing the OLD format is the point of this DEBUG door
    private fun plantLegacyToken() {
        runCatching {
            val key = androidx.security.crypto.MasterKey.Builder(this)
                .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM).build()
            val old = androidx.security.crypto.EncryptedSharedPreferences.create(
                this, "studio_oauth", key,
                androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
            val ok = old.edit().putString("selftest",
                """{"access":"planted-access","refresh":"planted-refresh","expires":null}""").commit()
            android.util.Log.i("AWSECRET", "planted legacy token ok=$ok")
        }.onFailure { android.util.Log.w("AWSECRET", "plant failed: $it") }
    }

    private fun checkMigratedToken() {
        val t = app.archivewatch.android.studio.StudioTokenStore.load(this, "selftest")
        val oldGone = !java.io.File(applicationInfo.dataDir, "shared_prefs/studio_oauth.xml").exists()
        val raw = java.io.File(applicationInfo.dataDir, "shared_prefs/studio_oauth_v2.xml")
            .takeIf { it.exists() }?.readText().orEmpty()
        android.util.Log.i("AWSECRET", "migrated access=${t?.access} refresh=${t?.refresh} " +
            "oldFileGone=$oldGone plaintextOnDisk=${raw.contains("planted")}")
        app.archivewatch.android.studio.StudioTokenStore.clear(this, "selftest")
        android.util.Log.i("AWSECRET", "after clear: ${app.archivewatch.android.studio.StudioTokenStore.load(this, "selftest")}")
    }

    /** While casting, the volume keys belong to the television (CastSupport). */
    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        val up = event.keyCode == android.view.KeyEvent.KEYCODE_VOLUME_UP
        if ((up || event.keyCode == android.view.KeyEvent.KEYCODE_VOLUME_DOWN) && CastSupport.isCasting()) {
            if (event.action == android.view.KeyEvent.ACTION_DOWN) CastSupport.stepCastVolume(up)
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        PlaybackPresence.inPip.value = isInPictureInPictureMode
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
        // PictureInPictureParams is API 26; the Fire TV flavor installs from 23.
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) return
        // From Android 12 the system has already entered it (auto-enter, onCreate).
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) return
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
        runCatching {
            enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(pipAspect()).build())
        }
    }

    /** Where the film sits inside the player view (fitted, centered), so the
     *  PiP window grows out of the picture rather than the letterbox. */
    private fun filmRect(view: android.graphics.Rect?): android.graphics.Rect? {
        if (view == null || view.isEmpty) return null
        val ar = pipAspect().toFloat()
        val vw = view.width().toFloat(); val vh = view.height().toFloat()
        val (w, h) = if (vw / vh > ar) (vh * ar) to vh else vw to (vw / ar)
        val l = view.left + ((vw - w) / 2).toInt(); val t = view.top + ((vh - h) / 2).toInt()
        return android.graphics.Rect(l, t, l + w.toInt(), t + h.toInt())
    }

    /** Android rejects PiP aspect ratios outside [1:2.39 .. 2.39:1]; anything out
     *  of range (or an unknown video size) falls back to 16:9. */
    private fun pipAspect(): Rational {
        val w = PlaybackPresence.aspectWidth
        val h = PlaybackPresence.aspectHeight
        val ratio = if (h > 0) w.toFloat() / h else 0f
        return if (ratio in 0.42f..2.39f) Rational(w, h) else Rational(16, 9)
    }

    /** archivewatch://item/{id} (same scheme as tvOS/iOS) and verified App
        Links from https://archivewatch.org/item/{id} + /series/{slug} → the
        matching surface. */
    private fun handleDeepLink(intent: Intent?) {
        // Verification hook, mirroring the Apple apps' AW_START_TAB (SCRATCHPAD
        // 2026-06-10). Driving a TV surface by counting blind D-pad presses is
        // fragile — focus lands on the nearest item, not a fixed one — so tests
        // jump straight to a tab:
        //   adb shell am start -n <pkg>/<act> --es aw_start_tab search
        // No-op in normal use: nothing sends this extra.
        intent?.getStringExtra("aw_start_tab")?.let { DeepLinks.pendingTab.value = it }
        // ...and straight to a pushed ROUTE, so no screen has to be reached by
        // counting D-pad presses (which lands on the nearest item, not a fixed
        // one, and has repeatedly steered automated checks to the wrong screen).
        intent?.getStringExtra("aw_start_route")?.let { DeepLinks.pendingRoute.value = it }
        // ...and straight into Watch Together Studio on a given film, so §9.4's
        // readout can be SEEN without a Detail entry to press. The TV Detail
        // has none yet (TvDetailScreen is a separate surface), and this is the
        // same reason aw_start_route exists: a surface reached by counting
        // D-pad presses is a surface reached by accident.
        //
        // It still goes through the RIGHTS GATE — a verification hook that
        // skipped the gate would be testing something the product cannot do.
        intent?.getStringExtra("aw_studio_item")?.let { DeepLinks.pendingStudioItem.value = it }
        intent?.getStringExtra("aw_studio_chat")?.let { DeepLinks.pendingStudioChat.value = it }
        // A bench destination for the Studio — DEBUG ONLY. See
        // DeepLinks.pendingStudioDest: honouring this in a release build would
        // let any app redirect a host's broadcast. The values are never
        // logged (§5).
        if (BuildConfig.DEBUG) {
            // Every player this process builds plays at volume 0, so a test
            // on the owner's television is silent (Apple's AW_MUTE).
            if (intent?.getBooleanExtra("aw_mute", false) == true) DeepLinks.forceMute = true
            // The SecretStore migration, proved on the device's own Keystore:
            // plant a token in the OLD EncryptedSharedPreferences format, then (in
            // a fresh process) read it through the real StudioTokenStore.
            if (intent?.getBooleanExtra("aw_secret_plant", false) == true) plantLegacyToken()
            if (intent?.getBooleanExtra("aw_secret_check", false) == true) checkMigratedToken()
            // Ask the launcher to pin a widget (continue | pick | surprise): the
            // system's own "Add to home screen" sheet, which a person confirms.
            intent?.getStringExtra("aw_pin_widget")?.let { which ->
                val receiver = when (which) {
                    "continue" -> app.archivewatch.android.widgets.ContinueWatchingWidgetReceiver::class.java
                    "pick" -> app.archivewatch.android.widgets.PickOfDayWidgetReceiver::class.java
                    else -> app.archivewatch.android.widgets.SurpriseWidgetReceiver::class.java
                }
                val mgr = android.appwidget.AppWidgetManager.getInstance(this)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O &&
                    mgr.isRequestPinAppWidgetSupported) {
                    val ok = mgr.requestPinAppWidget(android.content.ComponentName(this, receiver), null, null)
                    android.util.Log.i("AWWIDGET", "pin $which requested=$ok")
                }
            }
            val roomCode = intent?.getStringExtra("aw_room_join")
            val roomFilm = intent?.getStringExtra("aw_room_film")
            if (roomCode != null && roomFilm != null) {
                DeepLinks.pendingRoomJoin.value = roomCode to roomFilm
            }
            // The layout, so each placement can be VERIFIED on a device rather
            // than only unit-tested. The Apple doors take AW_STUDIO_LAYOUT.
            intent?.getStringExtra("aw_studio_layout")?.let {
                app.archivewatch.android.studio.StudioController.layout =
                    app.archivewatch.android.studio.StudioLayout.from(it)
            }
            intent?.getStringExtra("aw_studio_dest")?.let { DeepLinks.pendingStudioDest.value = it }
            intent?.getStringExtra("aw_studio_key")?.let { DeepLinks.pendingStudioKey.value = it }
            // The CONTROL for the foreground service's proof (A15): the same
            // show with the service never started.
            app.archivewatch.android.studio.StudioController.debugSkipForegroundService =
                intent?.getBooleanExtra("aw_studio_no_fgs", false) == true
            intent?.getStringExtra("aw_play_url")?.let { DeepLinks.pendingPlayURL.value = it }
            // Starts Twitch's device flow and prints what a HOST would be
            // shown. DEBUG only, and it exists because Android has the auth
            // chain before it has a screen to put it on: this proves the chain
            // reaches Twitch with the real client id, on real hardware, without
            // waiting for the UI.
            //
            // What is printed is exactly what belongs on a television — the
            // verification URI and the 8-character user code. The DEVICE code
            // is the polling credential and the access token is the session, so
            // neither is ever logged (§5).
            if (intent?.getBooleanExtra("aw_twitch_signin", false) == true) {
                Thread {
                    runCatching { StudioPlatformAuth.begin() }
                        .onSuccess {
                            android.util.Log.i("AWTWITCH",
                                "open ${it.verificationUri} and enter ${it.userCode}")
                        }
                        .onFailure {
                            android.util.Log.e("AWTWITCH", "begin failed: ${it.message}")
                        }
                }.start()
            }
        }
        if (intent?.getBooleanExtra("aw_focus_log", false) == true) {
            app.archivewatch.android.ui.tv.TvFocusLogging = true
        }

        val uri = intent?.data ?: return
        // A SHARED PLAYLIST FIRST, before any scheme or host check: it arrives
        // as an ordinary https link because the whole point is that it opens
        // for somebody with no app at all. The playlist is INSIDE the url, so
        // this resolves completely here with nothing to look up.
        app.archivewatch.android.data.PlaylistShare.sharedFrom(uri)?.let {
            DeepLinks.pendingSharedList.value = it
            return
        }
        if (uri.scheme == "archivewatch" && uri.host == "item") {
            uri.lastPathSegment?.let { DeepLinks.pendingItem.value = it }
            return
        }
        if (uri.scheme == "archivewatch" && uri.host == "series") {
            // tvOS scheme parity: archivewatch://series/{slug} — the catalog's
            // series card id is "series:<slug>".
            uri.pathSegments.firstOrNull()?.let { DeepLinks.pendingItem.value = "series:" + it }
            return
        }
        // Every RAIL destination has a door. The set used to be surprise,
        // channels and search, and TvAppRoot's own comment explained why that
        // mattered: a harness cannot open anything else deterministically —
        // synthetic taps are ignored on Android TV and Compose exposes no rail
        // focus. Verifying Collections on a real television therefore meant
        // walking the rail blind, which landed on a film's Detail page twice
        // in one session. A door per destination is cheaper than a harness
        // that guesses, and it is a real deep link for a viewer too.
        if (uri.scheme == "archivewatch" && uri.host in setOf(
                "surprise", "channels", "search", "collections", "cartoons",
                "library", "settings", "party",
            )
        ) {
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
