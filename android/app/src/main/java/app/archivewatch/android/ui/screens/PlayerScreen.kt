package app.archivewatch.android.ui.screens

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.net.Uri
import android.view.View
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import androidx.media3.ui.PlayerView
import app.archivewatch.android.BuildConfig
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.PlaySpec
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import app.archivewatch.android.cast.CastCaption
import app.archivewatch.android.cast.CastSupport
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.PlaybackPresence
import app.archivewatch.android.ui.tv.LocalIsTelevision
import app.archivewatch.android.ui.tv.tvFocusable
import app.archivewatch.android.ui.tv.ClaimInitialFocus
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.collectAsState
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Arrangement
import androidx.glance.appwidget.updateAll
import app.archivewatch.android.ui.tv.TvDims
import app.archivewatch.android.ui.tv.tvPlaybackKeys
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.IOException

/** Resolve the host Activity from a Compose context (the player is a pushed route in the
 *  single Activity, so fullscreen/orientation must act on — and restore — that Activity). */
private fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

private fun Activity.setImmersive(on: Boolean) {
    val controller = WindowCompat.getInsetsController(window, window.decorView)
    if (on) {
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
    } else {
        controller.show(WindowInsetsCompat.Type.systemBars())
    }
}

/**
 * Full-screen Media3 player. The Archive resets idle connections;
 * ExoPlayer's ranged loads + a patient LoadErrorHandlingPolicy resume
 * from the byte offset instead of failing playback — the Android analog
 * of the tvOS ResilientStreamLoader (Decision 021, plan §3). Never adds
 * a bitrate ceiling: the published derivative is highest-quality by policy.
 */
@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(container: AppContainer, nav: Nav, spec: PlaySpec) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val player = remember(spec.url) {
        val httpFactory = OkHttpDataSource.Factory(container.okHttp)
            .setUserAgent("ArchiveWatch-Android/1.0")
        val policy = object : DefaultLoadErrorHandlingPolicy() {
            override fun getRetryDelayMsFor(
                loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo,
            ): Long {
                // Network drops/resets: modest linear backoff, capped at 5s.
                if (loadErrorInfo.exception is IOException ||
                    loadErrorInfo.exception.cause is IOException
                ) {
                    return (1000L * loadErrorInfo.errorCount).coerceAtMost(5_000L)
                }
                return super.getRetryDelayMsFor(loadErrorInfo)
            }

            override fun getMinimumLoadableRetryCount(dataType: Int): Int = 8
        }
        // Time-prioritized buffering: the Archive resets idle connections, and
        // DefaultLoadControl's default byte cap (bitrate-derived) banks only a
        // few seconds for a high-bitrate progressive MP4 — too little to ride
        // out a reset. Buffer by TIME with deep headroom (~120s cap avoids the
        // high-bitrate OOM path where targetBufferBytes balloons). The tvOS
        // ResilientStreamLoader pins 300s; this is the Android analog.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                50_000,   // minBufferMs
                120_000,  // maxBufferMs
                2_500,    // bufferForPlaybackMs
                5_000,    // bufferForPlaybackAfterRebufferMs
            )
            .setPrioritizeTimeOverSizeThresholds(true)  // buffer by TIME not bytes
            .setBackBuffer(30_000, true)                // cheap re-seek without refetch
            .build()
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(httpFactory).setLoadErrorHandlingPolicy(policy),
            )
            .setLoadControl(loadControl)
            .build()
            .apply {
                // Binge queue (episodes): all entries load as Media3 items so
                // end-of-item advance + next/previous are native behavior.
                // The viewer's per-title copy choice (ArchiveVersions, the
                // tvOS picker's port) beats the pipeline's pick.
                val mediaItems = if (spec.queue.isNotEmpty()) {
                    spec.queue.map { e ->
                        MediaItem.Builder()
                            .setUri(app.archivewatch.android.data.ArchiveVersions.preferredURL(context, e.id, e.url))
                            .setMediaId(e.id)
                            .setMediaMetadata(
                                MediaMetadata.Builder()
                                    .setTitle(e.title)
                                    .setSubtitle(e.subtitle)
                                    .build(),
                            )
                            .build()
                    }
                } else {
                    listOf(
                        MediaItem.Builder()
                            .setUri(app.archivewatch.android.data.ArchiveVersions.preferredURL(context, spec.id, spec.url))
                            .setMediaId(spec.id)
                            // Side-loaded subtitles (Decision 039): Media3 plays
                            // SRT/VTT natively and lists them in the subtitle
                            // button. English (auto) defaults on.
                            .setSubtitleConfigurations(
                                spec.captions.map { c ->
                                    MediaItem.SubtitleConfiguration.Builder(Uri.parse(c.url))
                                        .setMimeType(
                                            if (c.format == "vtt") MimeTypes.TEXT_VTT
                                            else MimeTypes.APPLICATION_SUBRIP,
                                        )
                                        .setLanguage(c.lang)
                                        .setLabel(c.displayLabel)
                                        .setSelectionFlags(
                                            if (c.lang == "en") C.SELECTION_FLAG_DEFAULT else 0,
                                        )
                                        .build()
                                },
                            )
                            .setMediaMetadata(
                                MediaMetadata.Builder()
                                    .setTitle(spec.title)
                                    .setSubtitle(spec.subtitle)
                                    .setDescription(spec.description)
                                    .build(),
                            )
                            .build(),
                    )
                }
                setMediaItems(mediaItems, spec.queueIndex.coerceIn(0, mediaItems.size - 1),
                              spec.startPositionMs)
                if (spec.startMuted) volume = 0f
                playWhenReady = true
                prepare()
            }
    }

    // Lock-screen / notification media controls (the MediaSession parity row).
    //
    // ⚠️ TV-NP: a *video* app must NOT surface background/Now-Playing media
    // controls on TV, and must pause when the user switches away. So the
    // MediaSession is phone/tablet ONLY — on TV it is a quality-review failure,
    // not a feature (docs/TV-DESIGN.md §5.4, Decision 047).
    val isTv = LocalIsTelevision.current
    val mediaSession = remember(player, isTv) {
        if (isTv) null else MediaSession.Builder(context, player).build()
    }
    DisposableEffect(mediaSession) { onDispose { mediaSession?.release() } }

    // TV-NP, second half: pause on switch-away. On phones the player keeps
    // going (background audio + PiP are deliberate parity features); on TV it
    // must stop.
    if (isTv) {
        val lifecycleOwner = LocalLifecycleOwner.current
        DisposableEffect(lifecycleOwner, player) {
            val observer = LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_STOP) player.pause()
            }
            lifecycleOwner.lifecycle.addObserver(observer)
            onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
        }
    }

    // Resume when 10s < saved position < 95% of duration. Channel lineups
    // skip this (join-in-progress beats per-title resume).
    LaunchedEffect(spec.id) {
        if (!spec.persistProgress || spec.startPositionMs > 0) return@LaunchedEffect
        container.userState.progressFor(spec.id)?.let { saved ->
            if (saved.isResumable) player.seekTo(saved.positionMs)
        }
    }

    // Persist progress every 10s — against the CURRENT queue item, so each
    // binged episode resumes independently.
    LaunchedEffect(spec.id) {
        if (!spec.persistProgress) return@LaunchedEffect
        while (true) {
            delay(5_000)
            val duration = player.duration
            val id = player.currentMediaItem?.mediaId ?: spec.id
            if (duration > 0) {
                container.userState.saveProgress(id, player.currentPosition, duration)
            }
        }
    }

    DisposableEffect(spec.url) {
        onDispose {
            val duration = player.duration
            val position = player.currentPosition
            val id = player.currentMediaItem?.mediaId ?: spec.id
            val endedTitle = player.currentMediaItem?.mediaMetadata?.title?.toString() ?: spec.title
            android.util.Log.i("AWTV", "player dispose id=$id pos=$position dur=$duration persist=${spec.persistProgress}")
            player.release()
            if (duration > 0 && spec.persistProgress) {
                // container.scope, NOT the composable's rememberCoroutineScope:
                // this runs in onDispose, when the composition scope is being
                // cancelled — a launch on it silently never executes (the
                // Watch Next publish was a no-op until this was measured on
                // the Google TV, 2026-08-27; the periodic 5s ticker is what
                // made resume work all along).
                container.scope.launch {
                    container.userState.saveProgress(id, position, duration)
                    runCatching {
                        app.archivewatch.android.widgets.ContinueWatchingWidget()
                            .updateAll(context)
                    }
                    // Google TV launcher row (PARITY §8): the viewer's own
                    // resume state, nothing else (TV-DESIGN §1.4). Finished
                    // films leave the row.
                    if (position >= duration * 95 / 100) {
                        app.archivewatch.android.data.TvWatchNext.remove(context, id)
                    } else if (position > 10_000) {
                        val poster = container.catalog.db?.item(id)?.posterURL
                        app.archivewatch.android.data.TvWatchNext.publishResume(
                            context, id, endedTitle, poster, position, duration,
                        )
                    }
                }
            }
        }
    }

    // Title + description overlay that fades in/out IN SYNC with the transport
    // controls. Media3 exposes the controller's visibility natively
    // (setControllerVisibilityListener) — no timer mirroring needed. The text
    // tracks the CURRENT item so a binged episode updates it on advance.
    var controlsVisible by remember { mutableStateOf(true) }
    var playerViewRef by remember { mutableStateOf<PlayerView?>(null) }
    var nowTitle by remember { mutableStateOf(spec.title) }
    var nowDescription by remember { mutableStateOf(spec.description) }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onMediaItemTransition(item: MediaItem?, reason: Int) {
                item?.mediaMetadata?.let { md ->
                    nowTitle = md.title?.toString() ?: spec.title
                    nowDescription = md.description?.toString() ?: md.subtitle?.toString()
                }
            }

            override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) {
                // Feed the real video aspect to PiP so the window isn't 16:9-forced
                // for a 4:3 archival film.
                if (videoSize.width > 0 && videoSize.height > 0) {
                    PlaybackPresence.aspectWidth = videoSize.width
                    PlaybackPresence.aspectHeight = videoSize.height
                }
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }

    // Publish playback presence so MainActivity can auto-enter PiP on leave, and
    // ALWAYS restore orientation + system bars when the player route is popped
    // (covers backing out while in the fullscreen/landscape state).
    DisposableEffect(Unit) {
        PlaybackPresence.active.value = true
        onDispose {
            PlaybackPresence.active.value = false
            context.findActivity()?.let { activity ->
                activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                activity.setImmersive(false)
            }
        }
    }

    // Cast hand-off (backlog C4). Deliberately POLLED rather than wired to a
    // SessionManagerListener: that type only exists in the google flavor, and
    // referencing it here would break the structural GMS split that keeps Fire
    // TV safe (docs/TV-DESIGN.md §6.6). Polling costs nothing — it runs only
    // while the player is on screen, and the whole block compiles away to a
    // no-op on amazon, where IS_SUPPORTED is a const false.
    //
    // Not offered on TV: a television is a Cast RECEIVER, not a sender.
    if (!isTv && CastSupport.IS_SUPPORTED) {
        var handedOff by remember(spec.url) { mutableStateOf(false) }
        LaunchedEffect(spec.url) {
            while (true) {
                delay(700)
                val casting = CastSupport.isCasting()
                if (casting && !handedOff) {
                    val ok = CastSupport.loadMedia(
                        url = spec.url,
                        title = spec.title,
                        description = spec.description,
                        // VTT only. The receiver is handed a URL it fetches
                        // itself and parses as text/vtt; an .srt would simply
                        // fail there. The pipeline publishes a vttURL for
                        // essentially every caption, so this drops almost
                        // nothing (Decision 039).
                        captions = spec.captions
                            .filter { it.format.equals("vtt", true) || it.url.endsWith(".vtt", true) }
                            .map { CastCaption(it.lang, it.displayLabel, it.url) },
                        positionMs = player.currentPosition,
                    )
                    if (ok) {
                        handedOff = true
                        player.pause()      // the TV owns playback; don't double the audio
                    }
                } else if (!casting && handedOff) {
                    handedOff = false       // route ended — pick it back up here
                    player.play()
                }
            }
        }
    }

    // TV overlay visibility is OUR OWN state machine: tvPlaybackKeys consumes
    // the remote before Media3's controller ever shows, so the controller
    // visibility listener NEVER fires on TV — controlsVisible sat at its
    // initial value forever (measured on the Google TV 2026-08-27: the title
    // overlay never faded, and a Back gated on it became a Back TRAP, §1.7).
    // Any handled key shows the overlay; it fades after 4s of playback.
    var tvInteraction by remember { mutableStateOf(0) }
    var showTvMenu by remember { mutableStateOf(false) }
    var showPhoneMenu by remember { mutableStateOf(false) }
    // Picture-in-Picture: no chrome at all. The PiP tile is a thumbnail; the
    // title overlay and Media3's controller both covered the film there
    // (user report with screenshots, 2026-09-03).
    val inPip by PlaybackPresence.inPip.collectAsState()
    val overlayVisible = controlsVisible && !inPip
    if (isTv) {
        LaunchedEffect(tvInteraction) {
            controlsVisible = true
            delay(4_000)
            // A slow archive start must not pin the overlay: wait for real
            // playback, then fade. A paused film keeps its overlay (the
            // viewer paused to read it).
            while (!player.isPlaying) delay(500)
            controlsVisible = false
        }
        // The ten-foot Back contract (tvOS parity): overlay visible -> Back
        // dismisses it; only a second Back leaves the film. The options panel
        // takes precedence (registered later = wins).
        androidx.activity.compose.BackHandler(enabled = controlsVisible && !showTvMenu) {
            controlsVisible = false
        }
        androidx.activity.compose.BackHandler(enabled = showTvMenu) {
            showTvMenu = false
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            // TV-PC / TV-PP (docs/TV-DESIGN.md §5.2). Media3's PlayerView
            // handles most remote keys once its controller has focus, but the
            // quality bar is that these ALWAYS work during playback — including
            // while the controller is hidden, which is when a viewer is most
            // likely to press them. Handled explicitly rather than assumed.
            .then(
                if (isTv) {
                    Modifier.tvPlaybackKeys(
                        player,
                        onInteraction = { tvInteraction += 1 },
                        onMenu = { showTvMenu = true },
                    )
                } else Modifier,
            ),
    ) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    playerViewRef = this
                    useController = true
                    keepScreenOn = true
                    setShowNextButton(spec.queue.size > 1)
                    setShowPreviousButton(spec.queue.size > 1)
                    setShowSubtitleButton(true)   // archive files rarely carry tracks; harmless when absent
                    setControllerVisibilityListener(
                        PlayerView.ControllerVisibilityListener { visibility ->
                            if (BuildConfig.DEBUG) android.util.Log.i("AWPLAYER", "controller visibility=$visibility")
                            controlsVisible = visibility == View.VISIBLE
                        },
                    )
                    // Registering this listener is what makes Media3 draw the
                    // fullscreen button. Toggle landscape + immersive system bars;
                    // both are restored on dispose (the player shares the Activity).
                    setFullscreenButtonClickListener { isFullScreen ->
                        val activity = ctx.findActivity() ?: return@setFullscreenButtonClickListener
                        if (isFullScreen) {
                            activity.requestedOrientation =
                                ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                            activity.setImmersive(true)
                        } else {
                            activity.requestedOrientation =
                                ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                            activity.setImmersive(false)
                        }
                    }
                }
            },
            update = { view ->
                view.player = player
                if (view.useController == inPip) {
                    view.useController = !inPip
                    if (inPip) view.hideController()
                }
            },
            modifier = Modifier.fillMaxSize(),
        )

        // Phone: a slim top bar that fades WITH the transport controls — back,
        // the title on one line, and an options button (captions / speed /
        // copies / autoplay). The synopsis is not drawn over a film on a
        // phone: three lines of prose across a 4:3 frame was the "unnecessary
        // text" a user reported, and the sheet below is where the real
        // choices live. TV keeps its title + description overlay (TV-DESIGN).
        if (!isTv) {
            AnimatedVisibility(
                visible = overlayVisible,
                enter = fadeIn(),
                exit = fadeOut(),
                modifier = Modifier.align(Alignment.TopStart).fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            Brush.verticalGradient(
                                listOf(Color.Black.copy(alpha = 0.6f), Color.Transparent),
                            ),
                        )
                        .windowInsetsPadding(WindowInsets.systemBars)
                        .padding(horizontal = 4.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = { nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Color.White)
                    }
                    Text(
                        text = nowTitle,
                        style = MaterialTheme.typography.titleMedium,
                        color = Color.White,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    if (CastSupport.IS_SUPPORTED) {
                        // Sized explicitly: unbounded in a Row, the
                        // MediaRouteButton measured to the whole remaining
                        // width and a full screen of height, which pushed the
                        // title and options button off screen and centred the
                        // back arrow mid-film (Pixel 8a, first build).
                        AndroidView(
                            factory = { ctx -> CastSupport.createCastButton(ctx) ?: View(ctx) },
                            modifier = Modifier.padding(horizontal = 4.dp).size(48.dp),
                        )
                    }
                    IconButton(onClick = { showPhoneMenu = true }) {
                        Icon(Icons.Default.MoreVert, contentDescription = "Player options", tint = Color.White)
                    }
                }
            }
        }

        AnimatedVisibility(
            visible = isTv && overlayVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.TopStart).fillMaxWidth(),
        ) {
            // A top scrim keeps white text legible over bright frames (the
            // bottom transport bar already has Media3's own scrim).
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Black.copy(alpha = 0.55f), Color.Transparent),
                        ),
                    )
                    .windowInsetsPadding(WindowInsets.systemBars)
                    // TVs report no system-bar insets, so the phone's 20/16dp
                    // put the title hard against the panel edge where overscan
                    // clips it (docs/TV-DESIGN.md §4.2 — artwork may cross that
                    // line, text may not). Caught on the emulator.
                    .padding(
                        horizontal = if (isTv) TvDims.OverscanH else 20.dp,
                        vertical = if (isTv) TvDims.OverscanV else 16.dp,
                    ),
            ) {
                Text(
                    text = nowTitle,
                    style = MaterialTheme.typography.titleLarge,
                    color = Color.White,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                nowDescription?.takeIf { it.isNotBlank() }?.let { desc ->
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = desc,
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White.copy(alpha = 0.85f),
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }

        // The Cast affordance is Google's own MediaRouteButton (device picker,
        // connection states and accessibility for free), placed in the phone
        // top bar above. Renders nothing when Cast is unusable.

        if (!isTv && showPhoneMenu) {
            PhonePlayerOptionsSheet(
                player = player,
                spec = spec,
                container = container,
                onDismiss = { showPhoneMenu = false },
            )
        }

        if (isTv && showTvMenu) {
            TvPlayerOptionsPanel(
                player = player,
                spec = spec,
                container = container,
                onDismiss = { showTvMenu = false },
            )
        }
    }
}

/**
 * The phone's in-player options: Subtitles, Speed, Copies, Autoplay — the
 * things a viewer actually reaches for mid-film, on a native M3 bottom sheet
 * (the iOS player's menu, in the Android idiom). Media3's own gear covers
 * speed too; this sheet is the one place ALL of them are discoverable.
 */
@androidx.annotation.OptIn(UnstableApi::class)
@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PhonePlayerOptionsSheet(
    player: ExoPlayer,
    spec: PlaySpec,
    container: AppContainer,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val autoplay by container.settings.autoplayNext.collectAsState(initial = false)
    var speed by remember { mutableStateOf(player.playbackParameters.speed) }
    var textOff by remember {
        mutableStateOf(player.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }
    var textLang by remember {
        mutableStateOf(player.trackSelectionParameters.preferredTextLanguages.firstOrNull() ?: "en")
    }
    var versions by remember {
        mutableStateOf<List<app.archivewatch.android.data.ArchiveVersions.Version>?>(null)
    }
    var chosenVersion by remember {
        mutableStateOf(app.archivewatch.android.data.ArchiveVersions.chosenName(context, spec.id))
    }
    LaunchedEffect(spec.id) {
        if (spec.queue.isEmpty()) versions = app.archivewatch.android.data.ArchiveVersions.list(spec.id)
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(bottom = 16.dp),
        ) {
            if (player.hasNextMediaItem()) {
                ListItem(
                    headlineContent = { Text("Play next episode") },
                    modifier = Modifier.clickable { player.seekToNextMediaItem(); onDismiss() },
                )
                HorizontalDivider()
            }

            Text(
                "Speed",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 4.dp),
            )
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f).forEach { s ->
                    FilterChip(
                        selected = speed == s,
                        onClick = {
                            speed = s
                            player.setPlaybackSpeed(s)
                        },
                        label = { Text(if (s == 1f) "1x" else "${s}x") },
                    )
                }
            }

            Text(
                "Subtitles",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
            )
            if (spec.captions.isEmpty()) {
                Text(
                    "No subtitles are published for this copy. Use Get Subtitles on the title page.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            } else {
                ListItem(
                    headlineContent = { Text("Off") },
                    leadingContent = { RadioButton(selected = textOff, onClick = null) },
                    modifier = Modifier.clickable {
                        player.trackSelectionParameters = player.trackSelectionParameters
                            .buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
                        textOff = true
                    },
                )
                spec.captions.forEach { c ->
                    ListItem(
                        headlineContent = { Text(c.displayLabel) },
                        leadingContent = {
                            RadioButton(selected = !textOff && textLang == c.lang, onClick = null)
                        },
                        modifier = Modifier.clickable {
                            player.trackSelectionParameters = player.trackSelectionParameters
                                .buildUpon()
                                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                                .setPreferredTextLanguage(c.lang)
                                .build()
                            textOff = false
                            textLang = c.lang
                        },
                    )
                }
            }

            versions?.takeIf { it.isNotEmpty() }?.let { v ->
                Text(
                    "Copies",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
                )
                v.forEach { ver ->
                    ListItem(
                        headlineContent = { Text(ver.label) },
                        leadingContent = { RadioButton(selected = chosenVersion == ver.name, onClick = null) },
                        modifier = Modifier.clickable {
                            app.archivewatch.android.data.ArchiveVersions.choose(context, spec.id, ver)
                            chosenVersion = ver.name
                            val pos = player.currentPosition
                            player.currentMediaItem?.buildUpon()?.setUri(ver.url)?.build()?.let {
                                player.setMediaItem(it, pos)
                                player.prepare()
                                player.play()
                            }
                            onDismiss()
                        },
                    )
                }
            }

            HorizontalDivider(Modifier.padding(top = 12.dp))
            ListItem(
                headlineContent = { Text("Autoplay next") },
                trailingContent = {
                    Switch(
                        checked = autoplay,
                        onCheckedChange = { on -> scope.launch { container.settings.setAutoplayNext(on) } },
                    )
                },
            )
        }
    }
}

/**
 * The tvOS transport-bar menu, as the native Android TV in-player options
 * panel (D-pad UP / MENU): Play Next, Mute, Subtitles, Autoplay Next, and
 * Choose a Copy — mid-film, position-preserving.
 */
@Composable
private fun TvPlayerOptionsPanel(
    player: androidx.media3.exoplayer.ExoPlayer,
    spec: PlaySpec,
    container: AppContainer,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var muted by remember { mutableStateOf(player.volume == 0f) }
    val autoplay by container.settings.autoplayNext.collectAsState(initial = false)
    var versions by remember {
        mutableStateOf<List<app.archivewatch.android.data.ArchiveVersions.Version>?>(null)
    }
    var chosenVersion by remember {
        mutableStateOf(app.archivewatch.android.data.ArchiveVersions.chosenName(context, spec.id))
    }
    var textOff by remember {
        mutableStateOf(player.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }
    LaunchedEffect(spec.id) {
        if (spec.queue.isEmpty()) {
            versions = app.archivewatch.android.data.ArchiveVersions.list(spec.id)
        }
    }
    val firstFocus = remember { androidx.compose.ui.focus.FocusRequester() }
    ClaimInitialFocus(firstFocus)

    Box(Modifier.fillMaxSize().background(Color(0x99000000))) {
        Column(
            Modifier
                .align(Alignment.CenterEnd)
                .fillMaxHeight()
                .fillMaxWidth(0.42f)
                .background(Color(0xFF141414))
                .padding(horizontal = 32.dp, vertical = TvDims.OverscanV),
        ) {
            Text(
                "Player Options",
                style = MaterialTheme.typography.titleMedium,
                color = Color.White,
                modifier = Modifier.padding(bottom = 14.dp),
            )
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (player.hasNextMediaItem()) {
                    item(key = "next") {
                        TvMenuRow("Play Next Episode", null, firstFocus) {
                            player.seekToNextMediaItem(); onDismiss()
                        }
                    }
                }
                item(key = "mute") {
                    TvMenuRow(
                        if (muted) "Unmute" else "Mute",
                        null,
                        if (player.hasNextMediaItem()) null else firstFocus,
                    ) {
                        muted = !muted
                        player.volume = if (muted) 0f else 1f
                    }
                }
                item(key = "autoplay") {
                    TvMenuRow("Autoplay next", if (autoplay) "On" else "Off", null) {
                        scope.launch { container.settings.setAutoplayNext(!autoplay) }
                    }
                }
                if (spec.captions.isNotEmpty()) {
                    item(key = "subs-head") {
                        Text("Subtitles", style = MaterialTheme.typography.labelLarge,
                            color = Color(0xFF9A9A9A), modifier = Modifier.padding(top = 10.dp))
                    }
                    item(key = "subs-off") {
                        TvMenuRow("Off", if (textOff) "✓" else null, null) {
                            player.trackSelectionParameters = player.trackSelectionParameters
                                .buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
                            textOff = true
                        }
                    }
                    items(spec.captions.size, key = { "sub" + it }) { i ->
                        val c = spec.captions[i]
                        TvMenuRow(c.displayLabel, if (!textOff) "✓" else null, null) {
                            player.trackSelectionParameters = player.trackSelectionParameters
                                .buildUpon()
                                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                                .setPreferredTextLanguage(c.lang)
                                .build()
                            textOff = false
                        }
                    }
                }
                versions?.takeIf { it.isNotEmpty() }?.let { v ->
                    item(key = "ver-head") {
                        Text("Copies", style = MaterialTheme.typography.labelLarge,
                            color = Color(0xFF9A9A9A), modifier = Modifier.padding(top = 10.dp))
                    }
                    items(v.size, key = { v[it].name }) { i ->
                        val ver = v[i]
                        TvMenuRow(ver.label, if (chosenVersion == ver.name) "✓" else null, null) {
                            app.archivewatch.android.data.ArchiveVersions.choose(context, spec.id, ver)
                            chosenVersion = ver.name
                            // Swap mid-film, keeping the seat: buildUpon keeps
                            // metadata + subtitle configs; only the uri moves.
                            val pos = player.currentPosition
                            player.currentMediaItem?.buildUpon()?.setUri(ver.url)?.build()?.let {
                                player.setMediaItem(it, pos)
                                player.prepare()
                                player.play()
                            }
                            onDismiss()
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TvMenuRow(
    label: String,
    trailing: String?,
    focusRequester: androidx.compose.ui.focus.FocusRequester?,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .tvFocusable(
                onClick = onClick,
                focusRequester = focusRequester,
                shape = RoundedCornerShape(10.dp),
                scaleWhenFocused = 1.02f,
            )
            .background(Color(0xFF1F1F1F), RoundedCornerShape(10.dp))
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = Color.White,
            maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        trailing?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium, color = Color(0xFFFF5C35),
                modifier = Modifier.padding(start = 10.dp))
        }
    }
}
