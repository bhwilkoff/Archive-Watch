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

@androidx.annotation.OptIn(UnstableApi::class)
class StudioFilmAudioTap : TeeAudioProcessor.AudioBufferSink {

    /** The film's rate, and the channel count DELIVERED to [onPcm]: at most
     *  two. A 5.1 copy is folded to stereo here, before the mixer and the
     *  encoder, because the host's voice is a stereo ring read sample for
     *  sample — against six-channel buffers it was drained three times too
     *  fast and smeared into every speaker, the subwoofer included (measured
     *  on the Pixel, Caligari's 5.1 copy) — and a stereo AAC is what the
     *  ingests ask for. */
    @Volatile var sampleRate = 0; private set
    @Volatile var channelCount = 0; private set
    @Volatile private var sourceChannels = 0

    val buffersSeen = AtomicInteger(0)
    val bytesSeen = AtomicLong(0)
    /** Peak absolute sample, 0..1 — how the tap proves it heard SOUND rather
     *  than a correctly-plumbed silence. */
    @Volatile var peak = 0f; private set

    /** Called with 16-bit little-endian PCM, interleaved. */
    var onPcm: ((ByteArray, Int, Int) -> Unit)? = null

    override fun flush(sampleRateHz: Int, channelCount: Int, encoding: Int) {
        this.sampleRate = sampleRateHz
        this.sourceChannels = channelCount
        this.channelCount = minOf(channelCount, 2)
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
            val src = sourceChannels
            consumer(if (src > 2) toStereo(bytes, src) else bytes, sampleRate, channelCount)
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
                .setEnableAudioOutputPlaybackParameters(enableAudioTrackPlaybackParams)
                .setAudioProcessorChain(
                    DefaultAudioSink.DefaultAudioProcessorChain(
                        TeeAudioProcessor(this@StudioFilmAudioTap)))
                .build()
        }

    companion object {
        private const val MINUS_3DB = 0.7071f

        /**
         * Interleaved 16-bit PCM of [channels] > 2 folded to stereo. Android's
         * order is FL FR FC LFE BL BR for 5.1: centre and surrounds at -3 dB
         * (ITU-R BS.775), LFE dropped, scaled so a full-scale mix cannot clip.
         * Any other layout keeps its front pair.
         */
        fun toStereo(pcm: ByteArray, channels: Int): ByteArray {
            val frames = pcm.size / (2 * channels)
            val out = ByteArray(frames * 4)
            fun at(f: Int, c: Int): Float {
                val i = (f * channels + c) * 2
                return (((pcm[i + 1].toInt()) shl 8) or (pcm[i].toInt() and 0xFF)).toShort().toFloat()
            }
            val surround = channels == 6
            val norm = if (surround) 1f / (1f + 2 * MINUS_3DB) else 1f
            for (f in 0 until frames) {
                var l = at(f, 0); var r = at(f, 1)
                if (surround) {
                    val c = at(f, 2) * MINUS_3DB
                    l = (l + c + at(f, 4) * MINUS_3DB) * norm
                    r = (r + c + at(f, 5) * MINUS_3DB) * norm
                }
                val li = l.toInt().coerceIn(-32768, 32767); val ri = r.toInt().coerceIn(-32768, 32767)
                val o = f * 4
                out[o] = li.toByte(); out[o + 1] = (li shr 8).toByte()
                out[o + 2] = ri.toByte(); out[o + 3] = (ri shr 8).toByte()
            }
            return out
        }

        /** 16-bit PCM is what the tap expects; anything else is a surprise. */
        const val ENCODING = C.ENCODING_PCM_16BIT
    }
}
