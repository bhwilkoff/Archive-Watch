package app.archivewatch.android.studio

// Tapping the FILM's audio on Android (docs/WATCH-TOGETHER.md §6.2) — the
// counterpart of the Apple side's `MTAudioProcessingTap`.
//
// Media3's own guidance is that wrapping the `AudioSink` is NOT the way to
// intercept decoded PCM: `TeeAudioProcessor` exists for exactly this and
// guarantees the buffer lifecycle, so a tap cannot corrupt memory or stall
// the GC in the audio path. It is installed by overriding
// `DefaultRenderersFactory.buildAudioSink` and handing the chain an extra
// processor.
//
// The tap is a SPY, never a gate: it copies what goes past and returns
// immediately. The film keeps playing at full quality on the device whatever
// the broadcast is doing, which is §3 on every platform — the person in the
// room is watching a film, not monitoring a stream.

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.TeeAudioProcessor
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

@UnstableApi
class StudioFilmAudioTap : TeeAudioProcessor.AudioBufferSink {

    /** What the film actually is, once the first buffer has been seen. */
    @Volatile var sampleRate = 0; private set
    @Volatile var channelCount = 0; private set

    val buffersSeen = AtomicInteger(0)
    val bytesSeen = AtomicLong(0)
    /** Peak absolute sample, 0..1 — how the tap proves it heard SOUND rather
     *  than a correctly-plumbed silence. */
    @Volatile var peak = 0f; private set

    /** Called with 16-bit little-endian PCM, interleaved. */
    var onPcm: ((ByteArray, Int, Int) -> Unit)? = null

    override fun flush(sampleRateHz: Int, channelCount: Int, encoding: Int) {
        this.sampleRate = sampleRateHz
        this.channelCount = channelCount
    }

    override fun handleBuffer(buffer: ByteBuffer) {
        val remaining = buffer.remaining()
        if (remaining <= 0) return
        buffersSeen.incrementAndGet()
        bytesSeen.addAndGet(remaining.toLong())

        // THE IDLE PATH MUST NOT ALLOCATE. The renderers factory is chosen
        // when the player is BUILT, so once the tap is wired into the product
        // this runs on every film anyone plays, whether or not a broadcast
        // exists — and a per-buffer ByteArray on the audio path is a GC churn
        // nobody asked for. The peak is read straight out of the buffer with
        // ABSOLUTE gets (which do not move a position the renderer still
        // owns — the same reason duplicate() is used for the copy), and the
        // copy happens only when something is actually listening.
        val consumer = onPcm
        val dup = buffer.duplicate()
        val base = dup.position()
        var localPeak = peak
        var i = 0
        while (i + 1 < remaining) {
            val lo = dup.get(base + i).toInt() and 0xFF
            val hi = dup.get(base + i + 1).toInt()
            val a = kotlin.math.abs(((hi shl 8) or lo).toShort().toInt()) / 32768f
            if (a > localPeak) localPeak = a
            i += 64      // every 32nd frame is plenty for a peak
        }
        peak = localPeak
        if (consumer != null) {
            val bytes = ByteArray(remaining)
            dup.get(bytes)
            consumer(bytes, sampleRate, channelCount)
        }
    }

    /**
     * A renderers factory that plays the film normally AND copies its PCM
     * here. Everything else about playback is Media3's default.
     */
    fun renderersFactory(context: android.content.Context): DefaultRenderersFactory =
        object : DefaultRenderersFactory(context) {
            override fun buildAudioSink(
                context: android.content.Context,
                enableFloatOutput: Boolean,
                enableAudioTrackPlaybackParams: Boolean,
            ): AudioSink = DefaultAudioSink.Builder(context)
                .setEnableFloatOutput(enableFloatOutput)
                .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                .setAudioProcessorChain(
                    DefaultAudioSink.DefaultAudioProcessorChain(
                        TeeAudioProcessor(this@StudioFilmAudioTap)))
                .build()
        }

    companion object {
        /** 16-bit PCM is what the tap expects; anything else is a surprise. */
        const val ENCODING = C.ENCODING_PCM_16BIT
    }
}
