package app.archivewatch.android.player

// Audio Sync: a per-session nudge for a copy whose sound drifts from its
// picture (a videotape transfer that slips partway through). ANDROID-DESIGN
// §5.4, TV-DESIGN §5.7.
//
// SIGN: "+" means the SOUND comes LATER, the way a viewer says it ("the sound
// comes too early, push it later"); "-" means the sound comes earlier.
//
// HOW: Media3 has no audio-offset API. Every video frame is released against
// the player's clock, which is the audio sink's playout position, so the
// shift is applied to the VIDEO renderer's view of that clock and to nothing
// else: it is asked to render at clock + offset. With +1000 ms the picture
// shows frame T while the sound plays T - 1 s, i.e. the sound is 1 s later.
//
// The shift is deliberately NOT applied to the audio sink's reported
// position (a ForwardingAudioSink), although that also moves the picture:
// that position IS the player's position, so it would move the scrubber,
// the progress saved to history, the Watch Together room's clock and the
// MediaSession by the offset, and the audio renderer's monotonic clamp would
// freeze it on every step back. Here the clock is untouched: what the viewer
// sees on the scrubber and what is saved is the true position.

import android.content.Context
import android.os.Handler
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ForwardingRenderer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.video.VideoRendererEventListener
import kotlin.math.abs

/** The current nudge, read by the playback thread on every render. */
class AudioSyncOffset {
    @Volatile var offsetMs: Int = 0
        private set

    fun set(ms: Int) { offsetMs = clamp(ms) }
    fun nudge(steps: Int) = set(offsetMs + steps * STEP_MS)
    fun reset() = set(0)

    /** The position, in renderer time, the video renderer is asked to render at. */
    fun videoPositionUs(clockUs: Long): Long = videoPositionUs(clockUs, offsetMs)

    companion object {
        const val STEP_MS = 100
        const val LIMIT_MS = 2_000

        fun clamp(ms: Int): Int {
            val stepped = Math.round(ms / STEP_MS.toFloat()) * STEP_MS
            return stepped.coerceIn(-LIMIT_MS, LIMIT_MS)
        }

        fun videoPositionUs(clockUs: Long, offsetMs: Int): Long = clockUs + offsetMs * 1_000L

        /** "0 s", "+0.3 s", "-1.2 s". */
        fun label(ms: Int): String {
            if (ms == 0) return "0 s"
            val a = abs(ms)
            return (if (ms > 0) "+" else "-") + "${a / 1000}.${(a % 1000) / 100} s"
        }
    }
}

/** Renders the wrapped video renderer against the clock shifted by the offset.
 *  Seeks (resetPosition) pass through unshifted: they are the true position. */
@UnstableApi
class AudioSyncVideoRenderer(
    renderer: Renderer,
    private val offset: AudioSyncOffset,
) : ForwardingRenderer(renderer) {
    override fun render(positionUs: Long, elapsedRealtimeUs: Long) =
        super.render(offset.videoPositionUs(positionUs), elapsedRealtimeUs)

    override fun getDurationToProgressUs(positionUs: Long, elapsedRealtimeUs: Long): Long =
        super.getDurationToProgressUs(offset.videoPositionUs(positionUs), elapsedRealtimeUs)
}

/**
 * Media3's default renderers with every video renderer wrapped for Audio Sync.
 * [audioSink] composes with the Studio's film tap (StudioFilmAudioTap), which
 * owns the sink when present.
 */
@UnstableApi
class AudioSyncRenderersFactory(
    context: Context,
    private val offset: AudioSyncOffset,
    private val audioSink: ((Context, Boolean, Boolean) -> AudioSink)? = null,
) : DefaultRenderersFactory(context) {

    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioOutputPlaybackParams: Boolean,
    ): AudioSink? = audioSink?.invoke(context, enableFloatOutput, enableAudioOutputPlaybackParams)
        ?: super.buildAudioSink(context, enableFloatOutput, enableAudioOutputPlaybackParams)

    override fun buildVideoRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        eventHandler: Handler,
        eventListener: VideoRendererEventListener,
        allowedVideoJoiningTimeMs: Long,
        out: ArrayList<Renderer>,
    ) {
        val first = out.size
        super.buildVideoRenderers(context, extensionRendererMode, mediaCodecSelector,
            enableDecoderFallback, eventHandler, eventListener, allowedVideoJoiningTimeMs, out)
        for (i in first until out.size) out[i] = AudioSyncVideoRenderer(out[i], offset)
    }
}
