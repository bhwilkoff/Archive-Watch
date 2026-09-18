package app.archivewatch.android.studio

// The Android half of Watch Together Studio's video path
// (docs/WATCH-TOGETHER.md §6.2): MediaCodec H.264 with an INPUT SURFACE, so a
// GLES program draws the composed program straight into the encoder and no
// pixel is ever read back. This is the place Android is cheaper than Apple,
// where Core Image renders into a CVPixelBuffer that VideoToolbox then reads.
//
// TWO CONVERSIONS THAT ARE EASY TO MISS, and both are silent when wrong:
//
//   1. MediaCodec emits **Annex-B** (00 00 00 01 start codes). RTMP wants
//      **AVCC** (4-byte big-endian length prefixes). A server fed Annex-B
//      accepts the publish and never identifies the track — which looks
//      exactly like a network problem.
//   2. The avcC record must be BUILT from csd-0 (SPS) and csd-1 (PPS), which
//      arrive in the output format, not in a buffer. Apple hands avcC over
//      ready-made; here it is assembled by hand.

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.view.Surface
import java.nio.ByteBuffer

class StudioVideoEncoder(
    private val width: Int,
    private val height: Int,
    private val frameRate: Int,
    private val bitrate: Int,
) {
    /** The surface a GLES context draws into. Valid after [start]. */
    lateinit var inputSurface: Surface
        private set

    /** The AVCDecoderConfigurationRecord, once the encoder has produced it. */
    var avcC: ByteArray? = null
        private set

    private var codec: MediaCodec? = null
    private val bufferInfo = MediaCodec.BufferInfo()

    fun start() {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT,
                       MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            // A keyframe every 2 s is what YouTube and Twitch ask for.
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            setInteger(MediaFormat.KEY_BITRATE_MODE,
                       MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
            // Baseline keeps every ingest and every cheap decoder happy; the
            // Apple side uses High, and matching that is a later measurement.
            setInteger(MediaFormat.KEY_PROFILE,
                       MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
        }
        val c = createAvcEncoder(format)
        if (app.archivewatch.android.BuildConfig.DEBUG) {
            // §9.uu: `createEncoderByType` returns the FIRST codec the system
            // lists for the type, which is not promised to be the hardware one.
            // A software AVC encoder at 720p would cap the program near the
            // ~13 fps being measured, so the codec's identity is the first
            // thing to establish before blaming the GPU or the dongle.
            val hw = if (android.os.Build.VERSION.SDK_INT >= 29)
                c.codecInfo.isHardwareAccelerated.toString() else "unknown<29"
            android.util.Log.i("AWSTUDIOCODEC", "video encoder=" + c.name +
                "  hardwareAccelerated=" + hw)
        }
        inputSurface = c.createInputSurface()
        c.start()
        codec = c
    }

    /**
     * An AVC encoder that is actually in HARDWARE, or the system's choice.
     *
     * `createEncoderByType` returns the first codec the platform lists for the
     * type, and it is not promised to be hardware. On the Google TV it
     * returned `c2.android.avc.encoder` — Android's SOFTWARE AVC encoder — so
     * every program frame was encoded on the CPU, which capped the whole
     * pipeline at ~13 fps and made the GL draw expensive besides: a software
     * encoder consumes the input Surface by reading it back, and the GL driver
     * pays for that inside the draw (§9.uu).
     *
     * Each candidate is configured before being accepted, because a hardware
     * encoder may refuse this format (Baseline + CBR at 720p) and refusing at
     * `configure` is the only way to find out. A codec that refuses is
     * released and the next is tried; if none accepts, the platform's own
     * choice is used and the show still goes out — slowly, rather than not at
     * all.
     */
    private fun createAvcEncoder(format: MediaFormat): MediaCodec {
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            val all = android.media.MediaCodecList(
                android.media.MediaCodecList.REGULAR_CODECS).codecInfos
            if (app.archivewatch.android.BuildConfig.DEBUG) {
                // Say what the SELECTOR saw, not what we hoped it would see:
                // "no hardware encoder was chosen" and "this device has no
                // hardware encoder" are different facts (§9.uu).
                for (i in all) {
                    if (!i.isEncoder) continue
                    if (i.supportedTypes.none {
                            it.equals(MediaFormat.MIMETYPE_VIDEO_AVC, ignoreCase = true) }) continue
                    val vc = try {
                        i.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).videoCapabilities
                    } catch (_: Exception) { null }
                    android.util.Log.i("AWSTUDIOCODEC", "candidate " + i.name +
                        " hw=" + i.isHardwareAccelerated +
                        " fits" + width + "x" + height + "=" +
                        (vc?.isSizeSupported(width, height)) +
                        " maxW=" + vc?.supportedWidths?.upper +
                        " maxH=" + vc?.supportedHeights?.upper)
                }
            }
            for (info in all) {
                if (!info.isEncoder || !info.isHardwareAccelerated) continue
                if (info.supportedTypes.none {
                        it.equals(MediaFormat.MIMETYPE_VIDEO_AVC, ignoreCase = true) }) continue
                // NO `isSizeSupported` GATE. It reports FALSE for 1280x720 on
                // the encoder that is demonstrably encoding 1280x720 on this
                // device (maxW/maxH both 1808), so using it as a filter would
                // silently reject a perfectly good HARDWARE encoder on a phone
                // and fall back to software without saying why. `configure` is
                // the honest test and it is two lines below.
                var candidate: MediaCodec? = null
                try {
                    candidate = MediaCodec.createByCodecName(info.name)
                    candidate.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    return candidate
                } catch (_: Exception) {
                    try { candidate?.release() } catch (_: Exception) {}
                }
            }
        }
        val fallback = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        fallback.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        return fallback
    }

    /**
     * Drains whatever the encoder has ready. Calls [onFrame] with AVCC bytes.
     * Non-blocking: a live pipeline must never wait on the encoder.
     */
    fun drain(onFrame: (avcc: ByteArray, isKeyframe: Boolean, ptsMs: Int) -> Unit) {
        val c = codec ?: return
        while (true) {
            val index = c.dequeueOutputBuffer(bufferInfo, 0)
            if (index == MediaCodec.INFO_TRY_AGAIN_LATER) return
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                avcC = buildAvcC(c.outputFormat)
                continue
            }
            if (index < 0) continue
            val buf = c.getOutputBuffer(index) ?: continue
            buf.position(bufferInfo.offset)
            buf.limit(bufferInfo.offset + bufferInfo.size)
            val isConfig = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
            if (isConfig) {
                // The config buffer is the SPS+PPS again, in Annex-B. Keep it
                // only if the format change has not already given us avcC.
                if (avcC == null) avcC = buildAvcCFromAnnexB(toByteArray(buf))
            } else {
                val annexB = toByteArray(buf)
                val key = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0
                onFrame(annexBToAvcc(annexB), key, (bufferInfo.presentationTimeUs / 1000).toInt())
            }
            c.releaseOutputBuffer(index, false)
        }
    }

    /**
     * Asks the encoder for a keyframe on the next frame.
     *
     * A broadcast must BEGIN with one. Until a keyframe arrives a viewer who
     * joins — and a server that is recording — has nothing it can decode, so
     * the stream is live and the picture is absent. Found on a Google TV
     * (2026-09-17): mediamtx logged "recording" and "recording stopped" and
     * wrote no file at all, because it was still waiting for the first
     * decodable frame when the publisher hung up.
     */
    /**
     * §6.5: the one quality dial that may move mid-broadcast. Resolution and
     * frame rate are fixed for the life of an RTMP publish, so this changes
     * neither.
     *
     * Android binds this HARDER than Apple does: the format is configured
     * `BITRATE_MODE_CBR`, so the codec tracks the target rather than treating
     * it as a soft average. On Apple the same step moved the wire only 7%
     * until `DataRateLimits` was tightened from 2× to 1.15× (§9.y) — there is
     * no equivalent knob to get wrong here.
     */
    fun setBitrate(bps: Int) {
        val c = codec ?: return
        c.setParameters(android.os.Bundle().apply {
            putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bps)
        })
        currentBitrate = bps
    }

    @Volatile var currentBitrate: Int = bitrate
        private set

    fun requestKeyframe() {
        val c = codec ?: return
        c.setParameters(android.os.Bundle().apply {
            putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
        })
    }

    fun stop() {
        try { codec?.stop() } catch (_: Exception) {}
        try { codec?.release() } catch (_: Exception) {}
        codec = null
    }

    companion object {
        private fun toByteArray(b: ByteBuffer): ByteArray {
            val out = ByteArray(b.remaining()); b.get(out); return out
        }

        /** Splits an Annex-B stream into NAL payloads (no start codes). */
        fun splitAnnexB(d: ByteArray): List<ByteArray> {
            val starts = ArrayList<Int>()
            var i = 0
            while (i < d.size - 3) {
                if (d[i] == 0.toByte() && d[i + 1] == 0.toByte() && d[i + 2] == 1.toByte()) {
                    starts.add(i + 3); i += 3
                } else i++
            }
            val out = ArrayList<ByteArray>(starts.size)
            for (n in starts.indices) {
                var end = if (n + 1 < starts.size) starts[n + 1] - 3 else d.size
                // A start code may be 4 bytes (00 00 00 01); the extra zero
                // belongs to the separator, not to the NAL before it.
                while (end > starts[n] && d[end - 1] == 0.toByte()) end--
                out.add(d.copyOfRange(starts[n], end))
            }
            return out
        }

        /** Annex-B to AVCC: every start code becomes a 4-byte length. */
        fun annexBToAvcc(d: ByteArray): ByteArray {
            val nals = splitAnnexB(d)
            var size = 0
            for (n in nals) size += 4 + n.size
            val out = ByteArray(size)
            var o = 0
            for (n in nals) {
                out[o] = (n.size ushr 24).toByte(); out[o + 1] = (n.size ushr 16).toByte()
                out[o + 2] = (n.size ushr 8).toByte(); out[o + 3] = n.size.toByte()
                System.arraycopy(n, 0, out, o + 4, n.size); o += 4 + n.size
            }
            return out
        }

        fun buildAvcC(format: MediaFormat): ByteArray? {
            val sps = format.getByteBuffer("csd-0")?.let { toByteArray(it) } ?: return null
            val pps = format.getByteBuffer("csd-1")?.let { toByteArray(it) } ?: return null
            return buildAvcC(splitAnnexB(sps).firstOrNull() ?: return null,
                             splitAnnexB(pps).firstOrNull() ?: return null)
        }

        fun buildAvcCFromAnnexB(d: ByteArray): ByteArray? {
            val nals = splitAnnexB(d)
            val sps = nals.firstOrNull { (it[0].toInt() and 0x1F) == 7 } ?: return null
            val pps = nals.firstOrNull { (it[0].toInt() and 0x1F) == 8 } ?: return null
            return buildAvcC(sps, pps)
        }

        /** The AVCDecoderConfigurationRecord, ISO/IEC 14496-15 §5.2.4.1. */
        fun buildAvcC(sps: ByteArray, pps: ByteArray): ByteArray {
            val out = ArrayList<Byte>(11 + sps.size + pps.size)
            out.add(1)                       // configurationVersion
            out.add(sps[1])                  // AVCProfileIndication
            out.add(sps[2])                  // profile_compatibility
            out.add(sps[3])                  // AVCLevelIndication
            out.add(0xFF.toByte())           // 6 bits reserved + lengthSizeMinusOne = 3
            out.add(0xE1.toByte())           // 3 bits reserved + numOfSPS = 1
            out.add((sps.size ushr 8).toByte()); out.add(sps.size.toByte())
            for (b in sps) out.add(b)
            out.add(1)                       // numOfPPS
            out.add((pps.size ushr 8).toByte()); out.add(pps.size.toByte())
            for (b in pps) out.add(b)
            return out.toByteArray()
        }
    }
}
