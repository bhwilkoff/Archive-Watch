package app.archivewatch.android

import app.archivewatch.android.studio.RtmpPublisher
import app.archivewatch.android.studio.RtmpStreamConfig
import app.archivewatch.android.studio.StudioEngine
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import java.io.File
import java.net.Socket

/**
 * WATCH-TOGETHER §6.6 on Android: is a severed link rebuilt?
 *
 * Before this, a dropped connection ended an Android broadcast silently —
 * exactly as it did on Apple until §6.6 was written. The readout said OFFLINE
 * and nothing acted.
 *
 * The assertion that carries the weight is the SERVER's: mediamtx must list
 * the path as ready AGAIN after the cut. Our own `reconnects` counter only
 * says we tried. And the control — the same run with no reconnection — must
 * NOT come back, or this test would pass on a server that never noticed.
 */
class RtmpReconnectTest {

    private val host = "127.0.0.1"
    private val mtxPort = 19351
    private val proxyPort = 19361
    private val severAfter = 5.0

    private fun up(p: Int): Boolean = try { Socket(host, p).use { true } } catch (_: Exception) { false }
    private fun apiIsUp(): Boolean = try {
        java.net.URL("http://$host:9997/v3/paths/list").readText().isNotEmpty()
    } catch (_: Exception) { false }

    /** Does the server itself call this path ready? */
    private fun serverHasPath(name: String): Boolean = try {
        java.net.URL("http://$host:9997/v3/paths/list").readText()
            .let { it.contains("\"$name\"") && it.contains("\"ready\":true") }
    } catch (_: Exception) { false }

    private fun config() = RtmpStreamConfig(
        width = 1280, height = 720, frameRate = 30.0, videoBitrate = 2_400_000,
        avcC = RealH264.avcC,
        audioSampleRate = 44100, audioChannels = 1, audioBitrate = 128_000,
        audioSpecificConfig = RealAac.asc)

    /** mediamtx needs MORE than a frame or two before it calls a path ready. */
    private fun burst(p: RtmpPublisher, from: Int, count: Int = 300) {
        for (i in from until from + count) {
            p.sendVideo(RealH264.idrAvcc, isKeyframe = true, ptsMs = i * 33, dtsMs = i * 33)
            p.sendAudio(RealAac.frame, ptsMs = i * 23)
        }
        p.flush()
    }

    private fun waitForReady(name: String, seconds: Long): Boolean {
        val deadline = System.currentTimeMillis() + seconds * 1000
        while (System.currentTimeMillis() < deadline) {
            if (serverHasPath(name)) return true
            Thread.sleep(200)
        }
        return false
    }

    private fun severProxy(): Process? {
        var dir: File? = File("").absoluteFile
        var found: File? = null
        while (dir != null && found == null) {
            val c = File(dir, "tools/rtmp_sever_proxy.py")
            if (c.exists()) found = c
            dir = dir.parentFile
        }
        if (found == null) return null
        return ProcessBuilder("/usr/bin/python3", found.absolutePath,
                              proxyPort.toString(), mtxPort.toString(), severAfter.toString())
            .redirectErrorStream(true).start()
    }

    /**
     * Runs one episode and reports whether the SERVER saw the stream come
     * back. `recover` chooses whether §6.6 is allowed to act, which makes the
     * two calls a matched pair rather than a test and a story.
     */
    private fun episode(path: String, recover: Boolean): Pair<Boolean, RtmpPublisher> {
        val p = RtmpPublisher()
        p.setQueueBudget(2_400_000, 128_000)
        p.publish("rtmp://$host:$proxyPort/live", path, config())
        burst(p, 0)
        assertTrue("the server never called the path ready BEFORE the cut — " +
                   "nothing about a reconnect can be concluded from this run",
                   waitForReady("live/$path", 6))

        // Hold past the sever.
        val until = System.currentTimeMillis() + ((severAfter + 3) * 1000).toLong()
        while (System.currentTimeMillis() < until) {
            p.sendVideo(RealH264.idrAvcc, isKeyframe = true, ptsMs = 99_000, dtsMs = 99_000)
            Thread.sleep(33)
        }

        if (recover) {
            var attempt = 0
            val giveUpAt = System.currentTimeMillis() + 20_000
            while (p.needsReconnect && System.currentTimeMillis() < giveUpAt) {
                attempt += 1
                try { p.reconnect() } catch (_: Exception) {
                    val back = StudioEngine.RECONNECT_BACKOFF_SECONDS[
                        minOf(attempt - 1, StudioEngine.RECONNECT_BACKOFF_SECONDS.size - 1)]
                    Thread.sleep(back * 1000)
                }
            }
            if (p.health.state == "publishing") burst(p, 10_000)
        }
        val cameBack = waitForReady("live/$path", 8)
        return cameBack to p
    }

    @Test fun `a severed link is rebuilt and the server sees the stream again`() {
        assumeTrue("no mediamtx on $host:$mtxPort — skipping", up(mtxPort))
        assumeTrue("mediamtx API not enabled on :9997 — skipping", apiIsUp())

        // ---- The CONTROL first, so a harness bug cannot hide behind a pass.
        val ctlProxy = severProxy()
        assumeTrue("no sever proxy script — skipping", ctlProxy != null)
        try {
            val deadline = System.currentTimeMillis() + 5000
            while (!up(proxyPort) && System.currentTimeMillis() < deadline) Thread.sleep(100)
            assumeTrue("proxy never listened — skipping", up(proxyPort))
            val (ctlCameBack, ctl) = episode("androidrecon_ctl", recover = false)
            println("§6.6/Android control — server saw it again: $ctlCameBack, " +
                    "state=${ctl.health.state}, reconnects=${ctl.health.reconnects}")
            assertTrue("the CONTROL came back without any reconnection, so the sever " +
                       "is not severing and a pass below would prove nothing", !ctlCameBack)
            ctl.close()
        } finally { ctlProxy?.destroyForcibly() }

        // ---- §6.6 itself.
        val proxy = severProxy()
        try {
            val deadline = System.currentTimeMillis() + 5000
            while (!up(proxyPort) && System.currentTimeMillis() < deadline) Thread.sleep(100)
            assumeTrue("proxy never listened — skipping", up(proxyPort))
            val (cameBack, p) = episode("androidrecon", recover = true)
            println("§6.6/Android — server saw it again: $cameBack, state=${p.health.state}, " +
                    "reconnects=${p.health.reconnects}, bytes=${p.health.bytesSent}")
            assertTrue("the publisher never reconnected", p.health.reconnects >= 1)
            assertEquals("publishing", p.health.state)
            assertTrue("mediamtx never called the path ready again after the cut — " +
                       "our own reconnect counter is not evidence that anything was ingested",
                       cameBack)
            p.close()
        } finally { proxy?.destroyForcibly() }
    }
}
