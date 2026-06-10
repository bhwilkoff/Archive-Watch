package app.archivewatch.android.ui.screens

import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
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
                                    .build(),
                            )
                            .build(),
                    )
                }
                setMediaItems(mediaItems, spec.queueIndex.coerceIn(0, mediaItems.size - 1), 0L)
                playWhenReady = true
                prepare()
            }
    }

    // Resume when 10s < saved position < 95% of duration.
    LaunchedEffect(spec.id) {
        container.userState.progressFor(spec.id)?.let { saved ->
            if (saved.isResumable) player.seekTo(saved.positionMs)
        }
    }

    // Persist progress every 10s — against the CURRENT queue item, so each
    // binged episode resumes independently.
    LaunchedEffect(spec.id) {
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
            if (duration > 0) {
                scope.launch { container.userState.saveProgress(id, position, duration) }
            }
        }
    }

    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                useController = true
                keepScreenOn = true
                setShowNextButton(spec.queue.size > 1)
                setShowPreviousButton(spec.queue.size > 1)
            }
        },
        update = { view -> view.player = player },
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    )
}
