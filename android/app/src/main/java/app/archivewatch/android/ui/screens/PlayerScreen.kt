package app.archivewatch.android.ui.screens

import android.view.View
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import androidx.media3.ui.PlayerView
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.PlaySpec
import app.archivewatch.android.ui.Nav
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.IOException

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
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(httpFactory).setLoadErrorHandlingPolicy(policy),
            )
            .build()
            .apply {
                // Binge queue (episodes): all entries load as Media3 items so
                // end-of-item advance + next/previous are native behavior.
                val mediaItems = if (spec.queue.isNotEmpty()) {
                    spec.queue.map { e ->
                        MediaItem.Builder()
                            .setUri(e.url)
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
                            .setUri(spec.url)
                            .setMediaId(spec.id)
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
                playWhenReady = true
                prepare()
            }
    }

    // Lock-screen / notification media controls (the MediaSession parity row).
    val mediaSession = remember(player) {
        MediaSession.Builder(context, player).build()
    }
    DisposableEffect(mediaSession) { onDispose { mediaSession.release() } }

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
            delay(10_000)
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
            player.release()
            if (duration > 0 && spec.persistProgress) {
                scope.launch { container.userState.saveProgress(id, position, duration) }
            }
        }
    }

    // Title + description overlay that fades in/out IN SYNC with the transport
    // controls. Media3 exposes the controller's visibility natively
    // (setControllerVisibilityListener) — no timer mirroring needed. The text
    // tracks the CURRENT item so a binged episode updates it on advance.
    var controlsVisible by remember { mutableStateOf(true) }
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
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    useController = true
                    keepScreenOn = true
                    setShowNextButton(spec.queue.size > 1)
                    setShowPreviousButton(spec.queue.size > 1)
                    setShowSubtitleButton(true)   // archive files rarely carry tracks; harmless when absent
                    setControllerVisibilityListener(
                        PlayerView.ControllerVisibilityListener { visibility ->
                            controlsVisible = visibility == View.VISIBLE
                        },
                    )
                }
            },
            update = { view -> view.player = player },
            modifier = Modifier.fillMaxSize(),
        )

        AnimatedVisibility(
            visible = controlsVisible,
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
                    .padding(horizontal = 20.dp, vertical = 16.dp),
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
    }
}
