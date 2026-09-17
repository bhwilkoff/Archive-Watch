package app.archivewatch.android.studio

// Watch Together Studio's RTMP/RTMPS client for Android — a direct port of
// `ArchiveWatch/Studio/RTMPPublisher.swift` (Decision 127: we own the
// transport, no third-party encoder).
//
// It is a PORT and not a rewrite on purpose. Every non-obvious constant below
// was measured against the real YouTube and Twitch ingests on 2026-09-17, and
// the ones that matter are the ones no specification mentions:
//
//   · `connect` MUST be transaction 1. YouTube hardcodes it. Two other
//     servers echoed whatever we sent and hid the bug for an afternoon.
//   · the connect object must be the FULL ffmpeg-shaped one. YouTube ignored
//     a connect carrying only app/type/flashVer/tcUrl and timed out on both
//     RTMP and RTMPS, while Twitch accepted the very same one — so "it works
//     on one platform" proves nothing about the other.
//   · `tcUrl` omits a DEFAULT port. YouTube ignored a tcUrl carrying `:443`.
//   · the output chunk size is negotiated AFTER connect, which is ffmpeg's
//     order, and stays 128 until then.
//   · YouTube's backup ingest is `/live2?backup=1` — the query belongs to the
//     APP, not to the stream key.
//
// Kotlin/JVM rather than Android-only by design: it speaks sockets and bytes
// and nothing else, so it runs from a desktop `main()` against a local
// mediamtx exactly as the Swift one was first proven, long before a phone is
// involved.

import java.io.BufferedInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI
import javax.net.ssl.SSLSocketFactory
import kotlin.random.Random

class RtmpException(message: String) : Exception(message)

/** What the publisher knows about itself, for a health readout. */
data class RtmpHealth(
    var state: String = "idle",
    var connectAcknowledged: Boolean = false,
    var bytesSent: Long = 0,
    var bytesReceived: Long = 0,
    var videoFramesSent: Long = 0,
    var videoFramesDropped: Long = 0,
    var lastError: String? = null,
)

data class RtmpStreamConfig(
    val width: Int,
    val height: Int,
    val frameRate: Double,
    val videoBitrate: Int,
    /** The AVCDecoderConfigurationRecord, which must be sent before any media. */
    val avcC: ByteArray,
    val audioSampleRate: Int,
    val audioChannels: Int,
    val audioBitrate: Int,
    /** AudioSpecificConfig for the AAC sequence header. */
    val audioSpecificConfig: ByteArray,
)

// MARK: - AMF0

sealed class Amf0 {
    data class Num(val value: Double) : Amf0()
    data class Bool(val value: Boolean) : Amf0()
    data class Str(val value: String) : Amf0()
    data class Obj(val fields: List<Pair<String, Amf0>>) : Amf0()
    object Null : Amf0()

    fun encode(out: MutableList<Byte>) {
        when (this) {
            is Num -> { out.add(0x00); out.addAll(be64(java.lang.Double.doubleToLongBits(value))) }
            is Bool -> { out.add(0x01); out.add(if (value) 1 else 0) }
            is Str -> {
                val b = value.toByteArray(Charsets.UTF_8)
                out.add(0x02); out.addAll(be16(b.size)); out.addAll(b.toList())
            }
            is Obj -> {
                out.add(0x03)
                for ((k, v) in fields) {
                    val kb = k.toByteArray(Charsets.UTF_8)
                    out.addAll(be16(kb.size)); out.addAll(kb.toList())
                    v.encode(out)
                }
                // The object end marker: an empty key then 0x09.
                out.addAll(be16(0)); out.add(0x09)
            }
            is Null -> out.add(0x05)
        }
    }

    companion object {
        private fun be16(v: Int) = listOf((v ushr 8).toByte(), v.toByte())
        private fun be64(v: Long) = (7 downTo 0).map { (v ushr (it * 8)).toByte() }
    }
}

// MARK: - The publisher

class RtmpPublisher {

    val health = RtmpHealth()

    /** `AW_RTMP_WIRE=1` prints every inbound message. The Swift port's
     *  transaction-id bug was found only this way. */
    private val wire = System.getenv("AW_RTMP_WIRE") == "1"

    private var socket: Socket? = null
    private var input: InputStream? = null
    private var output: DataOutputStream? = null

    private var app: String = ""
    private var streamKey: String = ""
    private var tcUrl: String = ""
    private var config: RtmpStreamConfig? = null

    /** 128 until Set Chunk Size is negotiated — see the header note. */
    private var outChunkSize = 128

    /**
     * THE SERVER'S chunk size, which is a different number from ours and
     * starts at the protocol default of 128 whatever we choose for our own
     * direction. Reading replies with the OUTBOUND size desynchronises the
     * parser the moment we raise ours to 4096, and the symptom is not a parse
     * error — it is an EOF, because the next byte read as a basic header is
     * really payload. The Swift publisher carries the same split for the same
     * reason.
     */
    private var inChunkSize = 128
    private var transactionId = 0
    private var streamId = 1
    private var sentSequenceHeaders = false
    private var startedAtMs: Long = 0

    /**
     * Address and key are separate because every platform hands them out
     * separately, and YouTube's backup ingest carries a query on the APP.
     */
    fun publish(server: String, key: String, config: RtmpStreamConfig, timeoutMs: Int = 10_000) {
        val uri = URI(server)
        val scheme = uri.scheme?.lowercase()
            ?: throw RtmpException("no scheme in $server")
        if (scheme != "rtmp" && scheme != "rtmps") throw RtmpException("not an RTMP url: $server")
        val host = uri.host ?: throw RtmpException("no host in $server")
        var appPath = (uri.path ?: "").trim('/')
        if (appPath.isEmpty()) throw RtmpException("no app path in $server")
        if (!uri.query.isNullOrEmpty()) appPath += "?" + uri.query

        val tls = scheme == "rtmps"
        val port = if (uri.port > 0) uri.port else if (tls) 443 else 1935
        // tcUrl WITHOUT a default port — YouTube ignored one carrying `:443`.
        val portSuffix = if (uri.port > 0) ":$port" else ""

        app = appPath
        streamKey = key
        tcUrl = "$scheme://$host$portSuffix/$app"
        this.config = config
        health.state = "connecting"

        val raw = Socket()
        raw.tcpNoDelay = true
        raw.connect(InetSocketAddress(host, port), timeoutMs)
        val s = if (tls) {
            (SSLSocketFactory.getDefault() as SSLSocketFactory)
                .createSocket(raw, host, port, true).also { (it as javax.net.ssl.SSLSocket).startHandshake() }
        } else raw
        s.soTimeout = timeoutMs
        socket = s
        input = BufferedInputStream(s.getInputStream())
        output = DataOutputStream(s.getOutputStream())

        health.state = "handshaking"
        handshake()
        health.state = "connected"

        // CONNECT FIRST, full object, transaction 1.
        invoke(
            "connect",
            listOf(
                Amf0.Obj(
                    listOf(
                        "app" to Amf0.Str(app),
                        "type" to Amf0.Str("nonprivate"),
                        "flashVer" to Amf0.Str("FMLE/3.0 (compatible; ArchiveWatch)"),
                        "tcUrl" to Amf0.Str(tcUrl),
                        "fpad" to Amf0.Bool(false),
                        "capabilities" to Amf0.Num(15.0),
                        "audioCodecs" to Amf0.Num(4071.0),
                        "videoCodecs" to Amf0.Num(252.0),
                        "videoFunction" to Amf0.Num(1.0),
                    )
                )
            ),
            streamID = 0, chunkStreamID = 3
        )
        readUntilResult()
        health.connectAcknowledged = true

        // Chunk size AFTER connect, which is ffmpeg's order.
        sendProtocolControl(1, be32(4096))
        outChunkSize = 4096

        invoke("releaseStream", listOf(Amf0.Null, Amf0.Str(streamKey)), 0, 3)
        invoke("FCPublish", listOf(Amf0.Null, Amf0.Str(streamKey)), 0, 3)
        invoke("createStream", listOf(Amf0.Null), 0, 3)
        readUntilResult()
        invoke("publish", listOf(Amf0.Null, Amf0.Str(streamKey), Amf0.Str("live")), streamId, 4)
        readUntilResult()

        sendMetadata(config)
        startedAtMs = System.currentTimeMillis()
        health.state = "publishing"
    }

    private fun handshake() {
        val out = output ?: throw RtmpException("not connected")
        val c0c1 = ByteArray(1 + 1536)
        c0c1[0] = 0x03
        val nowMs = System.currentTimeMillis().toInt()
        c0c1[1] = (nowMs ushr 24).toByte(); c0c1[2] = (nowMs ushr 16).toByte()
        c0c1[3] = (nowMs ushr 8).toByte(); c0c1[4] = nowMs.toByte()
        // bytes 5..8 stay zero (the "version" field); the rest is random.
        for (i in 9 until c0c1.size) c0c1[i] = Random.nextInt(256).toByte()
        out.write(c0c1); out.flush()
        health.bytesSent += c0c1.size

        val s0s1s2 = readExactly(1 + 1536 + 1536)
        if (s0s1s2[0] != 0x03.toByte()) {
            throw RtmpException("handshake failed: server version ${s0s1s2[0]}")
        }
        // C2 echoes S1.
        out.write(s0s1s2, 1, 1536); out.flush()
        health.bytesSent += 1536
    }

    /**
     * `connect` must be transaction 1, so the counter is incremented BEFORE
     * use and starts at zero. Getting this wrong is invisible against servers
     * that echo the id back.
     */
    private fun invoke(command: String, args: List<Amf0>, streamID: Int, chunkStreamID: Int) {
        transactionId += 1
        val body = mutableListOf<Byte>()
        Amf0.Str(command).encode(body)
        Amf0.Num(transactionId.toDouble()).encode(body)
        for (a in args) a.encode(body)
        sendMessage(type = 20, streamID = streamID, chunkStreamID = chunkStreamID,
                    payload = body.toByteArray(), timestamp = 0)
    }

    private fun sendMetadata(c: RtmpStreamConfig) {
        val body = mutableListOf<Byte>()
        Amf0.Str("@setDataFrame").encode(body)
        Amf0.Str("onMetaData").encode(body)
        // An ECMA array (type 8) is what every ingest expects here; it is an
        // object with a count in front.
        body.add(0x08)
        body.addAll(be32(9).toList())
        fun prop(k: String, v: Double) {
            val kb = k.toByteArray(Charsets.UTF_8)
            body.add((kb.size ushr 8).toByte()); body.add(kb.size.toByte())
            body.addAll(kb.toList())
            Amf0.Num(v).encode(body)
        }
        prop("duration", 0.0)
        prop("width", c.width.toDouble())
        prop("height", c.height.toDouble())
        prop("videodatarate", c.videoBitrate / 1000.0)
        prop("framerate", c.frameRate)
        prop("videocodecid", 7.0)          // AVC
        prop("audiodatarate", c.audioBitrate / 1000.0)
        prop("audiosamplerate", c.audioSampleRate.toDouble())
        prop("audiocodecid", 10.0)         // AAC
        body.add(0x00); body.add(0x00); body.add(0x09)
        sendMessage(18, streamId, 4, body.toByteArray(), 0)
    }

    private fun sendSequenceHeaders(c: RtmpStreamConfig) {
        // Video: AVC sequence header, sent ONCE. A live reader that attaches
        // later never sees it, which is why a mid-stream ffprobe reports
        // "h264 0x0" and why the server's own recording is the thing to
        // assert against.
        val v = mutableListOf<Byte>()
        v.add(((1 shl 4) or 7).toByte())   // keyframe + AVC
        v.add(0)                            // sequence header
        v.addAll(be24(0).toList())
        v.addAll(c.avcC.toList())
        sendMessage(9, streamId, 6, v.toByteArray(), 0)

        val a = mutableListOf<Byte>()
        a.add(0xAF.toByte())
        a.add(0)                            // sequence header
        a.addAll(c.audioSpecificConfig.toList())
        sendMessage(8, streamId, 5, a.toByteArray(), 0)
        sentSequenceHeaders = true
    }

    /** One encoded H.264 frame, already in AVCC (length-prefixed) form. */
    fun sendVideo(avccData: ByteArray, isKeyframe: Boolean, ptsMs: Int, dtsMs: Int) {
        val c = config ?: return
        if (health.state != "publishing") return
        if (!sentSequenceHeaders) sendSequenceHeaders(c)
        val compositionTime = (ptsMs - dtsMs).coerceAtLeast(0)
        val tag = mutableListOf<Byte>()
        tag.add((((if (isKeyframe) 1 else 2) shl 4) or 7).toByte())
        tag.add(1)                          // AVC NALU
        tag.addAll(be24(compositionTime).toList())
        tag.addAll(avccData.toList())
        sendMessage(9, streamId, 6, tag.toByteArray(), dtsMs)
        health.videoFramesSent += 1
    }

    /** One raw AAC frame (no ADTS header). */
    fun sendAudio(aacFrame: ByteArray, ptsMs: Int) {
        val c = config ?: return
        if (health.state != "publishing") return
        if (!sentSequenceHeaders) sendSequenceHeaders(c)
        val tag = mutableListOf<Byte>()
        tag.add(0xAF.toByte())
        tag.add(1)                          // raw frame
        tag.addAll(aacFrame.toList())
        sendMessage(8, streamId, 5, tag.toByteArray(), ptsMs)
    }

    fun close() {
        try { socket?.close() } catch (_: Exception) {}
        socket = null; input = null; output = null
        if (health.state != "failed") health.state = "closed"
    }

    // MARK: Chunking

    private fun sendProtocolControl(type: Int, payload: ByteArray) {
        sendMessage(type, 0, 2, payload, 0)
    }

    /**
     * Writes one message as fmt-0 plus fmt-3 continuations. Deliberately the
     * simple form: correctness first, and the saving from fmt-1/2 headers is a
     * handful of bytes against a 6 Mbps stream.
     */
    private fun sendMessage(type: Int, streamID: Int, chunkStreamID: Int,
                            payload: ByteArray, timestamp: Int) {
        val out = output ?: throw RtmpException("not connected")
        val extended = timestamp >= 0xFFFFFF
        val header = mutableListOf<Byte>()
        header.add(((0 shl 6) or chunkStreamID).toByte())
        header.addAll(be24(if (extended) 0xFFFFFF else timestamp).toList())
        header.addAll(be24(payload.size).toList())
        header.add(type.toByte())
        // Message stream id is LITTLE endian here, and only here.
        header.add(streamID.toByte()); header.add((streamID ushr 8).toByte())
        header.add((streamID ushr 16).toByte()); header.add((streamID ushr 24).toByte())
        if (extended) header.addAll(be32(timestamp).toList())
        out.write(header.toByteArray())

        var offset = 0
        while (offset < payload.size) {
            val take = minOf(outChunkSize, payload.size - offset)
            out.write(payload, offset, take)
            offset += take
            if (offset < payload.size) {
                out.write(byteArrayOf(((3 shl 6) or chunkStreamID).toByte()))
                if (extended) out.write(be32(timestamp))
            }
        }
        out.flush()
        health.bytesSent += header.size + payload.size
    }

    // MARK: Reading

    /**
     * Drains inbound chunks until a `_result` or `_error` arrives. Enough for
     * the connect/createStream/publish sequence; the streaming phase ignores
     * inbound traffic beyond keeping the socket drained.
     */
    private fun readUntilResult() {
        val deadline = System.currentTimeMillis() + 10_000
        while (System.currentTimeMillis() < deadline) {
            val msg = readMessage() ?: continue
            if (msg.first == 20) {
                val text = String(msg.second, Charsets.ISO_8859_1)
                if (text.contains("_error")) throw RtmpException("server refused: $text")
                if (text.contains("_result") || text.contains("onStatus")) return
            }
        }
        throw RtmpException("timed out waiting for the server to answer")
    }

    /** Returns (messageType, payload), or null for a chunk that is not yet whole. */
    private fun readMessage(): Pair<Int, ByteArray>? {
        val first = readExactly(1)[0].toInt() and 0xFF
        val fmt = first ushr 6
        val csid = first and 0x3F
        var length = 0
        var type = 0
        when (fmt) {
            0 -> { val h = readExactly(11); length = be24Of(h, 3); type = h[6].toInt() and 0xFF }
            1 -> { val h = readExactly(7); length = be24Of(h, 3); type = h[6].toInt() and 0xFF }
            2 -> { readExactly(3); return null }
            else -> return null
        }
        if (csid == 0) readExactly(1)
        if (csid == 1) readExactly(2)
        val body = ByteArray(length)
        var got = 0
        while (got < length) {
            val take = minOf(inChunkSize, length - got)
            val part = readExactly(take)
            System.arraycopy(part, 0, body, got, take)
            got += take
            if (got < length) readExactly(1)   // the fmt-3 continuation header
        }
        health.bytesReceived += length
        if (wire) {
            val head = if (type == 20) body.joinToString("") { c -> if (c in 32..126) c.toInt().toChar().toString() else "." } else body.take(24).joinToString("") { "%02x".format(it) }
            System.err.println("  <- fmt=$fmt csid=$csid type=$type len=$length $head")
        }
        // Type 1 is Set Chunk Size — the server telling us how IT will chunk.
        if (type == 1 && body.size >= 4) {
            inChunkSize = (((body[0].toInt() and 0x7F) shl 24) or
                           ((body[1].toInt() and 0xFF) shl 16) or
                           ((body[2].toInt() and 0xFF) shl 8) or
                           (body[3].toInt() and 0xFF))
        }
        return type to body
    }

    private fun readExactly(n: Int): ByteArray {
        val ins = input ?: throw RtmpException("not connected")
        val buf = ByteArray(n)
        var got = 0
        while (got < n) {
            val r = ins.read(buf, got, n - got)
            if (r < 0) throw EOFException("the server closed the connection")
            got += r
        }
        return buf
    }

    private fun be24Of(b: ByteArray, at: Int) =
        ((b[at].toInt() and 0xFF) shl 16) or ((b[at + 1].toInt() and 0xFF) shl 8) or (b[at + 2].toInt() and 0xFF)

    private fun be24(v: Int) = byteArrayOf((v ushr 16).toByte(), (v ushr 8).toByte(), v.toByte())
    private fun be32(v: Int) = byteArrayOf((v ushr 24).toByte(), (v ushr 16).toByte(), (v ushr 8).toByte(), v.toByte())
}
