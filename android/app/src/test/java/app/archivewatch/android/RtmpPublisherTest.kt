package app.archivewatch.android

import app.archivewatch.android.studio.Amf0
import app.archivewatch.android.studio.RtmpPublisher
import app.archivewatch.android.studio.RtmpStreamConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.net.InetSocketAddress
import java.net.Socket

/**
 * The Android RTMP publisher, proven the way the Swift one was: against a real
 * server, before any phone is involved (WATCH-TOGETHER §6.2, §8.1).
 *
 * The protocol tests need a local `mediamtx`. They SKIP rather than fail when
 * one is not listening, because a red X must mean "this is broken", never
 * "the developer did not start a server" (Decision 107). The pure-encoding
 * tests always run and are the ones CI can rely on.
 *
 *   mediamtx  (rtmpAddress: :19351)
 *   android/gradlew -p android :app:testGoogleDebugUnitTest --tests '*RtmpPublisherTest*'
 */
class RtmpPublisherTest {

    private val host = System.getenv("AW_RTMP_HOST") ?: "127.0.0.1"
    private val port = (System.getenv("AW_RTMP_PORT") ?: "19351").toInt()

    private fun serverIsUp(): Boolean = try {
        Socket().use { it.connect(InetSocketAddress(host, port), 500); true }
    } catch (_: Exception) { false }

    /**
     * THE SERVER'S OWN VIEW, which is the only thing here that cannot lie.
     *
     * The first version of this file asserted `publisher.health.state ==
     * "publishing"` — our own optimism, set the moment we stopped waiting for
     * a reply. All seven tests passed while mediamtx logged nothing but
     * `opened` then `closed: EOF`: it had never accepted a publish at all.
     * That is the same instrument bug the Swift destination harness had, where
     * counting any socket close as success printed PASS for five ingests while
     * YouTube was failing at the handshake.
     *
     * So the assertion is now: does the SERVER list a ready path with our
     * name on it?
     */
    private fun serverHasPath(name: String): Boolean = try {
        val json = java.net.URL("http://$host:9997/v3/paths/list").readText()
        json.contains("\"name\":\"$name\"") && json.contains("\"ready\":true")
    } catch (_: Exception) { false }

    private fun apiIsUp(): Boolean = try {
        java.net.URL("http://$host:9997/v3/paths/list").readText().isNotEmpty()
    } catch (_: Exception) { false }

    private fun config() = RtmpStreamConfig(
        width = 1920, height = 1080, frameRate = 30.0, videoBitrate = 6_000_000,
        // A REAL avcC and, below, a REAL IDR — both generated from an x264
        // keyframe (`RealH264.kt`). Hand-written bytes were not enough: a
        // server accepts the publish either way, but it cannot make the path
        // READY until it can actually parse the video, so a fake NAL made the
        // only honest assertion unreachable.
        avcC = RealH264.avcC,
        audioSampleRate = 44100, audioChannels = 1, audioBitrate = 128_000,
        // The AudioSpecificConfig must DESCRIBE the frames we actually send.
        // The generated fixture is AAC-LC 44.1 kHz MONO (asc 0x1208); a
        // hand-written stereo 0x1210 here would have the sequence header
        // contradicting the media, and a server cannot identify the track.
        audioSpecificConfig = RealAac.asc
    )

    // MARK: Encoding — no server needed

    @Test fun `amf0 string carries a big-endian length`() {
        val out = mutableListOf<Byte>()
        Amf0.Str("connect").encode(out)
        assertEquals(0x02.toByte(), out[0])
        assertEquals(0x00.toByte(), out[1])
        assertEquals(7.toByte(), out[2])
        assertEquals("connect", String(out.subList(3, out.size).toByteArray()))
    }

    @Test fun `amf0 number is an IEEE754 double, big-endian`() {
        val out = mutableListOf<Byte>()
        Amf0.Num(1.0).encode(out)
        // 1.0 is 0x3FF0000000000000.
        assertEquals(0x00.toByte(), out[0])
        assertEquals(0x3F.toByte(), out[1])
        assertEquals(0xF0.toByte(), out[2])
        for (i in 3..8) assertEquals(0.toByte(), out[i])
    }

    @Test fun `amf0 object ends with the empty-key marker`() {
        val out = mutableListOf<Byte>()
        Amf0.Obj(listOf("app" to Amf0.Str("live"))).encode(out)
        assertEquals(0x03.toByte(), out[0])
        assertEquals(0x00.toByte(), out[out.size - 3])
        assertEquals(0x00.toByte(), out[out.size - 2])
        assertEquals(0x09.toByte(), out[out.size - 1])
    }

    // MARK: The protocol, against a real server

    @Test fun `the SERVER reports a ready path, not just our own state`() {
        assumeTrue("no mediamtx on $host:$port — skipping", serverIsUp())
        assumeTrue("mediamtx API not enabled on :9997 — skipping", apiIsUp())
        val p = RtmpPublisher()
        p.publish("rtmp://$host:$port/live", "androidtest", config())
        assertEquals("publishing", p.health.state)
        assertTrue("the server never acknowledged connect", p.health.connectAcknowledged)
        // Real media has to flow before mediamtx calls a path ready — and
        // BOTH tracks, because the config declares audio and the server holds
        // the path back until it has identified every track it was promised.
        for (i in 0 until 30) {
            p.sendVideo(RealH264.idrAvcc, isKeyframe = true, ptsMs = i * 33, dtsMs = i * 33)
            p.sendAudio(RealAac.frame, ptsMs = i * 23)
        }
        var ready = false
        val deadline = System.currentTimeMillis() + 5000
        while (System.currentTimeMillis() < deadline && !ready) {
            ready = serverHasPath("live/androidtest"); if (!ready) Thread.sleep(200)
        }
        assertTrue("mediamtx never listed 'live/androidtest' as a ready path — " +
                   "our state said publishing and the server disagreed", ready)
        p.close()
    }

    /** Isolation: which track does the server fail to identify? */
    @Test fun `video-only publish is identified by the server`() {
        assumeTrue("no mediamtx on $host:$port — skipping", serverIsUp())
        assumeTrue("mediamtx API not enabled on :9997 — skipping", apiIsUp())
        val p = RtmpPublisher()
        p.publish("rtmp://$host:$port/live", "videoonly", config(), declareAudio = false)
        for (i in 0 until 30) {
            p.sendVideo(RealH264.idrAvcc, isKeyframe = true, ptsMs = i * 33, dtsMs = i * 33)
        }
        var ready = false
        val deadline = System.currentTimeMillis() + 6000
        while (System.currentTimeMillis() < deadline && !ready) {
            ready = serverHasPath("live/videoonly"); if (!ready) Thread.sleep(200)
        }
        p.close()
        assertTrue("video-only was not identified either", ready)
    }

    private fun avccFrame(nal: ByteArray): ByteArray {
        val avcc = ByteArray(4 + nal.size)
        avcc[0] = (nal.size ushr 24).toByte(); avcc[1] = (nal.size ushr 16).toByte()
        avcc[2] = (nal.size ushr 8).toByte(); avcc[3] = nal.size.toByte()
        System.arraycopy(nal, 0, avcc, 4, nal.size)
        return avcc
    }

    @Test fun `sends video and audio the server accepts`() {
        assumeTrue("no mediamtx on $host:$port — skipping", serverIsUp())
        val p = RtmpPublisher()
        p.publish("rtmp://$host:$port/live", "androidmedia", config())
        // One IDR-shaped access unit and one AAC frame. The content is not a
        // decodable picture; what is under test is the tag framing and the
        // chunking, which the server rejects loudly when wrong.
        for (i in 0 until 30) {
            p.sendVideo(RealH264.idrAvcc, isKeyframe = true, ptsMs = i * 33, dtsMs = i * 33)
            p.sendAudio(ByteArray(64) { 0x21 }, ptsMs = i * 33)
        }
        assertEquals("publishing", p.health.state)
        assertEquals(30L, p.health.videoFramesSent)
        assertTrue("nothing was written", p.health.bytesSent > 10_000)
        p.close()
    }

    @Test fun `a message larger than the chunk size is split and still accepted`() {
        assumeTrue("no mediamtx on $host:$port — skipping", serverIsUp())
        val p = RtmpPublisher()
        p.publish("rtmp://$host:$port/live", "androidchunk", config())
        // 40 KB against a 4096-byte chunk size: ten continuation headers. This
        // is the path a keyframe takes, and getting the fmt-3 header wrong
        // shows up as the server closing with "received type 1 chunk without
        // previous chunk" — which is exactly how the Swift port first failed.
        val big = ByteArray(40_000) { 0x41 }
        val avcc = ByteArray(4 + big.size)
        avcc[0] = (big.size ushr 24).toByte(); avcc[1] = (big.size ushr 16).toByte()
        avcc[2] = (big.size ushr 8).toByte(); avcc[3] = big.size.toByte()
        System.arraycopy(big, 0, avcc, 4, big.size)
        p.sendVideo(avcc, isKeyframe = true, ptsMs = 0, dtsMs = 0)
        Thread.sleep(400)
        assertEquals("the server dropped the connection on a split message",
                     "publishing", p.health.state)
        assertTrue(p.health.bytesSent > 40_000)
        p.close()
    }

    @Test fun `a bad host fails rather than pretending`() {
        val p = RtmpPublisher()
        val threw = try {
            p.publish("rtmp://127.0.0.1:1/live", "nope", config(), timeoutMs = 1500); false
        } catch (_: Exception) { true }
        assertTrue("a dead port must throw, not report success", threw)
        assertTrue(p.health.state != "publishing")
    }
}
