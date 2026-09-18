package app.archivewatch.android.studio

// AAC for the broadcast (docs/WATCH-TOGETHER.md §6.2). MediaCodec, fed the
// PCM the film tap copied out, producing the raw AAC frames RTMP wants.
//
// TWO THINGS RTMP NEEDS THAT AN ENCODER DOES NOT VOLUNTEER:
//
//   1. **Raw frames, not ADTS.** MediaCodec can emit either; an FLV audio tag
//      carries a raw frame and a 7-byte ADTS header inside one makes the
//      track undecodable while everything still "works". We never ask for
//      ADTS, and the check is that `csd-0` exists — an ADTS-configured
//      encoder does not produce one.
//   2. **The AudioSpecificConfig**, which arrives as `csd-0` in the output
//      format and must be published as the audio sequence header BEFORE any
//      frame. It has to DESCRIBE the frames actually sent: declaring stereo
//      while sending mono is a real bug this project has already made once
//      (§6.2a).

import android.media.MediaCodec
import android.media.MediaFormat
import java.nio.ByteBuffer

class StudioAacEncoder(
    private val sampleRate: Int,
    private val channelCount: Int,
    private val bitrate: Int = 128_000,
) {
    /** The AudioSpecificConfig, once the encoder has produced it. */
    var asc: ByteArray? = null
        private set

    /**
     * The encoder's priming delay in milliseconds — 2048 samples, which is
     * AAC-LC's usual two-frame lookahead. Overridable because it is a codec
     * property and a different device may differ; the measurement that sets it
     * is `tools/measure_av_sync.py`, never a guess.
     */
    val primingMillis: Int = (PRIMING_SAMPLES * 1000.0 / sampleRate).toInt()

    private var codec: MediaCodec? = null
    private val info = MediaCodec.BufferInfo()
    private var pcmBytesIn = 0L

    /** PCM the encoder could not take. Silent drops are how drift hides. */
    val droppedBytes = java.util.concurrent.atomic.AtomicLong(0)

    /**
     * Where this encoder's clock sits on the SHOW's timeline, in microseconds.
     *
     * The sample clock below counts from zero at the encoder's OWN start, and
     * the encoder is built when the first PCM arrives — which is after the
     * show began. Without this offset the audio claims to start at 0 while the
     * video is already seconds in, and the two tracks describe different
     * timelines (§9.pp).
     */
    @Volatile var startOffsetUs: Long = 0

    fun start() {
        val format = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channelCount).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE,
                       android.media.MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16 * 1024)
        }
        val c = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        c.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        c.start()
        codec = c
    }

    /** Queues 16-bit PCM. Non-blocking: audio must never wait on a codec. */
    fun encode(pcm: ByteArray) {
        val c = codec ?: return
        var offset = 0
        while (offset < pcm.size) {
            val index = c.dequeueInputBuffer(0)
            if (index < 0) {
                // FULL — drop rather than stall, but the dropped samples still
                // HAPPENED. The clock must advance past them or the audio
                // timeline falls behind real time by exactly what was dropped,
                // for the rest of the show: a 2.8% drop rate measured -3.09 s
                // of A/V drift over 110 s on the Google TV (§9.qq). Counting
                // OFFERED bytes turns a growing desync into one brief gap,
                // which a listener forgives and a desync never stops being.
                val lost = pcm.size - offset
                pcmBytesIn += lost
                droppedBytes.addAndGet(lost.toLong())
                return
            }
            val buf = c.getInputBuffer(index) ?: return
            buf.clear()
            val take = minOf(buf.capacity(), pcm.size - offset)
            buf.put(pcm, offset, take)
            // The timestamp is derived from BYTES CONSUMED, not the wall
            // clock: audio's clock is its own sample count, and using the
            // wall clock makes the stream drift whenever a frame is late.
            val us = startOffsetUs +
                     pcmBytesIn * 1_000_000L / (sampleRate.toLong() * channelCount * 2)
            c.queueInputBuffer(index, 0, take, us, 0)
            pcmBytesIn += take
            offset += take
        }
    }

    fun drain(onFrame: (aac: ByteArray, ptsMs: Int) -> Unit) {
        val c = codec ?: return
        while (true) {
            val index = c.dequeueOutputBuffer(info, 0)
            if (index == MediaCodec.INFO_TRY_AGAIN_LATER) return
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                asc = c.outputFormat.getByteBuffer("csd-0")?.let { toBytes(it) }
                continue
            }
            if (index < 0) continue
            val buf = c.getOutputBuffer(index)
            if (buf != null) {
                buf.position(info.offset); buf.limit(info.offset + info.size)
                val isConfig = (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                if (isConfig) {
                    if (asc == null) asc = toBytes(buf)
                } else {
                    // AAC ENCODER DELAY, subtracted here.
                    //
                    // AAC-LC does not produce the samples it was handed: its
                    // output lags its input by the codec's priming samples, so
                    // audio carrying an input timestamp arrives LATE against
                    // video carrying a frame timestamp. Measured on a Google TV
                    // with a synchronised flash-and-burst signal
                    // (tools/measure_av_sync.py): audio +50.5 ms and +45.0 ms
                    // across two recordings, spread 5–21 ms — a constant
                    // offset, not drift, and 2048 samples at 44.1 kHz is
                    // 46.4 ms.
                    //
                    // MP4 carries priming in an edit list; FLV has nowhere to
                    // put it, so the only place to correct it is the timestamp.
                    val ms = (info.presentationTimeUs / 1000).toInt() - primingMillis
                    onFrame(toBytes(buf), ms.coerceAtLeast(0))
                }
            }
            c.releaseOutputBuffer(index, false)
        }
    }

    fun stop() {
        try { codec?.stop() } catch (_: Exception) {}
        try { codec?.release() } catch (_: Exception) {}
        codec = null
    }

    companion object {
        /** AAC-LC's priming samples — see `primingMillis`. */
        const val PRIMING_SAMPLES = 2048
    }

    private fun toBytes(b: ByteBuffer): ByteArray {
        val out = ByteArray(b.remaining()); b.get(out); return out
    }
}
