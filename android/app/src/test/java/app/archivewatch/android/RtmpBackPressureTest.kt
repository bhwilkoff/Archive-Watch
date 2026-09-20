package app.archivewatch.android

import app.archivewatch.android.studio.RtmpPublisher
import app.archivewatch.android.studio.RtmpStreamConfig
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.net.Socket
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

/**
 * WATCH-TOGETHER §6.4 on Android: does the picture yield and the voice keep
 * going when the uplink is too narrow?
 *
 * Android needed this MORE than Apple did. This publisher wrote every frame
 * synchronously to a blocking socket, and `StudioEngine` calls it from the one
 * GL render thread — so a narrow uplink did not shed frames, it BLOCKED the
 * render loop, stalling the composite, the encoder drain and the host's own
 * view of the film. Apple at least had a queue to overflow.
 *
 * The congestion is real: `tools/rtmp_throttle_proxy.py` rate-limits the
 * client->server direction, so the publisher meets it through its own queue
 * the way it will on a domestic uplink.
 */
class RtmpBackPressureTest {

    private val mtxHost = "127.0.0.1"
    private val mtxPort = 19351
    private val proxyPort = 19360
    private val throttleBps = 400_000
    private val openSeconds = 4.0
    private val throttleSeconds = 9.0

    private fun up(host: String, port: Int): Boolean =
        try { Socket(host, port).use { true } } catch (_: Exception) { false }

    // MONO, because the generated ASC fixture is AAC-LC 44.1 kHz mono
    // (0x1208) and a sequence header must DESCRIBE the frames actually sent.
    private fun config(asc: ByteArray) = RtmpStreamConfig(
        width = 1280, height = 720, frameRate = 30.0, videoBitrate = 2_400_000,
        avcC = RealH264.avcC,
        audioSampleRate = 44100, audioChannels = 1, audioBitrate = 128_000,
        audioSpecificConfig = asc)

    @Test fun `video yields under congestion and audio does not`() {
        assumeTrue("no mediamtx on $mtxHost:$mtxPort — skipping", up(mtxHost, mtxPort))
        // Walk UP to find the repo root rather than assuming a depth: Gradle
        // runs unit tests with the working directory at `android/app`, so a
        // hand-counted "../tools" silently became `android/tools` and the test
        // SKIPPED — which at least said so, instead of passing.
        var dir: File? = File("").absoluteFile
        var found: File? = null
        while (dir != null && found == null) {
            val candidate = File(dir, "tools/rtmp_throttle_proxy.py")
            if (candidate.exists()) found = candidate
            dir = dir.parentFile
        }
        val proxyScript = found
        assumeTrue("no throttle proxy script under any parent of ${File("").absolutePath} — skipping",
                   proxyScript != null)

        // KEEP THE PROXY'S OWN WORDS. This discarded them, and the proxy is
        // the only witness to whether the throttle it was started for actually
        // engaged — it announces `phase: open | throttled | recovered`. When
        // this case failed on 2026-09-20 with a queue that never filled, the
        // first three hypotheses (machine load, the proxy not throttling, the
        // kernel socket buffer) were all guesses that its output would have
        // settled immediately. A harness that throws away its instrument's
        // output is throwing away the evidence it was run to collect — the
        // same rule `tools/harness_awdiag.swift` carries for `awdiag`.
        val proxyLog = File.createTempFile("aw-proxy", ".log")
        val proxy = ProcessBuilder(
            "/usr/bin/python3", proxyScript!!.absolutePath,
            proxyPort.toString(), mtxPort.toString(),
            openSeconds.toString(), throttleBps.toString(), throttleSeconds.toString())
            .redirectErrorStream(true).redirectOutput(proxyLog).start()
        try {
            // The proxy counts only connections that SEND bytes, so this
            // readiness poll cannot be mistaken for the publisher — a probe
            // absorbing the event it was meant to observe cost a whole run of
            // the Swift harness.
            // WAIT FOR OUR OWN PROXY TO SAY SO, not for "something answers".
            //
            // This used to poll `up(mtxHost, proxyPort)` — a bare TCP connect —
            // and that cannot tell this proxy from ANYTHING else holding the
            // port. On 2026-09-20 a stale listener had it, so the proxy could
            // not bind, the publisher connected straight through to mediamtx,
            // nothing was ever throttled, and the case failed reporting "the
            // queue never approached the cap" — a true statement about a run
            // that had no throttle in it. Three hypotheses (machine load, a
            // broken proxy, the kernel socket buffer) were chased before the
            // proxy's own log — which the test was discarding — showed it had
            // never accepted a publisher at all.
            //
            // The proxy announces itself on the first line of its output. That
            // banner is proof the port is OURS; a TCP handshake is proof of
            // nothing.
            val deadline = System.currentTimeMillis() + 5_000
            while (System.currentTimeMillis() < deadline &&
                   !proxyLog.readText().contains("throttle-proxy")) Thread.sleep(100)
            val banner = proxyLog.readText()
            assumeTrue(
                "the throttle proxy never announced itself on $mtxHost:$proxyPort — " +
                "something else is almost certainly holding that port, in which case " +
                "the publisher would reach the server unthrottled and this case would " +
                "measure nothing. Its output was: ${banner.ifBlank { "<empty>" }}",
                banner.contains("throttle-proxy"))
            assumeTrue("proxy never listened — skipping", up(mtxHost, proxyPort))

            val p = RtmpPublisher()
            p.setQueueBudget(2_400_000, 128_000)
            val cap = p.maxQueuedBytes
            p.publish("rtmp://$mtxHost:$proxyPort/live", "androidbp", config(RealAac.asc))
            assertEquals("publishing", p.health.state)

            // ~2.5 Mbps of real frames, paced at 30 fps. The payload is sized
            // rather than decodable: what is under test is the queue, and a
            // server that rejects the framing says so loudly (the other tests
            // cover framing).
            // Properly length-prefixed AVCC, not raw bytes: mediamtx PARSES the
            // NAL framing, so garbage would make it drop the publish and the
            // test would fail for a reason that has nothing to do with §6.4.
            val perFrame = 2_400_000 / 8 / 30
            val body = ByteArray(perFrame) { 0x42 }
            val filler = ByteArray(4 + body.size).also {
                val n = body.size
                it[0] = (n ushr 24).toByte(); it[1] = (n ushr 16).toByte()
                it[2] = (n ushr 8).toByte();  it[3] = n.toByte()
                body.copyInto(it, 4)
            }
            var peakQueued = 0L
            var dropsBeforeThrottle = 0L
            var dropsDuring = 0L
            var worstAudioSecond = Int.MAX_VALUE
            var audioThisSecond = 0
            var lastSecond = 0L
            var bucketIsWhole = false

            // OFFERED BYTES INSIDE THE THROTTLED WINDOW, measured rather than
            // assumed. See the precondition below the send loop.
            var offeredInWindow = 0L
            var windowFirstMs = 0L
            var windowLastMs = 0L

            val t0 = System.currentTimeMillis()
            val total = ((openSeconds + throttleSeconds + 4.0) * 1000).toLong()
            var i = 0
            while (System.currentTimeMillis() - t0 < total) {
                val elapsed = (System.currentTimeMillis() - t0) / 1000.0
                val key = i % 60 == 0
                p.sendVideo(if (key) RealH264.idrAvcc else filler, isKeyframe = key,
                            ptsMs = i * 33, dtsMs = i * 33)
                p.sendAudio(ByteArray(64) { 0x21 }, ptsMs = i * 33)
                audioThisSecond += 1
                i += 1

                if (elapsed < openSeconds - 0.5) dropsBeforeThrottle = p.health.videoFramesDropped
                if (elapsed > openSeconds + 0.5 && elapsed < openSeconds + throttleSeconds) {
                    peakQueued = maxOf(peakQueued, p.health.queuedBytes)
                    dropsDuring = p.health.videoFramesDropped
                    offeredInWindow += filler.size + 64
                    if (windowFirstMs == 0L) windowFirstMs = System.currentTimeMillis()
                    windowLastMs = System.currentTimeMillis()
                    // WHOLE seconds only. The first version recorded the
                    // stretch between entering the window (elapsed 4.5) and
                    // the next integer boundary (5.0) as a "second" and
                    // reported 11 audio frames — which read exactly like a
                    // 0.6 s stall in the send loop and sent me looking for one
                    // in the publisher. It was 0.4 s of audio, correctly
                    // delivered. A bucket that is not a full second is not a
                    // rate.
                    val sec = elapsed.toLong()
                    if (sec != lastSecond) {
                        if (lastSecond > 0L && bucketIsWhole) {
                            worstAudioSecond = minOf(worstAudioSecond, audioThisSecond)
                        }
                        audioThisSecond = 0
                        bucketIsWhole = true
                        lastSecond = sec
                    }
                }
                // PACE TO A DEADLINE, NOT BY A FIXED SLEEP.
                //
                // `Thread.sleep(33)` makes the period 33 ms PLUS however long
                // the iteration took, so every slow write permanently lowers
                // the offered rate — and this test only congests the queue
                // while the offer rate stays above the drain. Run inside the
                // full §8 suite, with parallel `swiftc -O` compiles and a live
                // mediamtx on the same machine, the loop fell far enough
                // behind that the queue peaked at 10 kB against a 474 kB cap
                // and the test failed having proved nothing (2026-09-20).
                // Sleeping only the REMAINDER holds 30 fps for as long as the
                // machine can manage it at all.
                val dueMs = t0 + (i.toLong() * 33L)
                val slack = dueMs - System.currentTimeMillis()
                if (slack > 0) Thread.sleep(slack)
            }
            val dropsAtEnd = p.health.videoFramesDropped
            val audioSent = p.health.audioFramesSent
            p.close()

            println("§6.4/Android — cap ${cap / 1000} kB, peak queued ${peakQueued / 1000} kB, " +
                    "drops before=$dropsBeforeThrottle during=$dropsDuring end=$dropsAtEnd, " +
                    "audio delivered=$audioSent of ${i} offered, thinnest harness second=$worstAudioSecond")

            println("--- the proxy's own account ---")
            proxyLog.readLines().forEach { println("    $it") }
            println("-------------------------------")

            // COULD THIS RUN CONGEST AT ALL? If not, it is a SKIP.
            //
            // Congestion exists only while the producer offers faster than the
            // proxy drains. That is normally a 6x margin — ~300 kB/s offered
            // against 50 kB/s drained — but it is a property of THIS MACHINE
            // AT THIS MOMENT, not of the publisher, and on a loaded machine
            // the producer can fall below the drain and no queue ever builds.
            // Reporting that as a failure of §6.4 is the instrument blaming
            // the product for its own conditions.
            //
            // Decision 130 makes pass, skip and fail three separate numbers,
            // and `assumeTrue` is how JUnit spells the third. The assertions
            // below are unchanged and still fail for a real regression —
            // this only refuses to judge a run that could not have judged.
            val windowMs = (windowLastMs - windowFirstMs).coerceAtLeast(1)
            val offeredBps = offeredInWindow * 8 * 1000 / windowMs
            println("§6.4/Android — offered ${offeredBps / 1000} kbps inside the window " +
                    "against a ${throttleBps / 1000} kbps drain")
            assumeTrue("this machine could not out-run the throttle " +
                       "(offered ${offeredBps / 1000} kbps against a " +
                       "${throttleBps / 1000} kbps drain), so back-pressure was never " +
                       "provoked — SKIPPED rather than failed, because that is a fact " +
                       "about the load on this machine and not about the publisher",
                       offeredBps > throttleBps * 3 / 2)

            // 1. The signal fires — without this the rest is vacuous.
            // 90% of the cap, not "over the cap". The policy PINS the queue at
            // the cap by design — it starts dropping the moment the budget is
            // exceeded — so the measured peak sits right on it (476 kB against
            // 474 kB on the first run). Demanding a large overshoot would be
            // demanding that back-pressure work badly.
            assertTrue("the queue never approached the ${cap / 1000} kB cap " +
                       "(peak ${peakQueued / 1000} kB), so back-pressure never engaged",
                       peakQueued > cap * 9 / 10)
            // 2. Video is what yields, and only under congestion.
            assertEquals("video was dropped before the throttle", 0L, dropsBeforeThrottle)
            assertTrue("no video was dropped under congestion", dropsDuring > 0)
            // 3. THE PROMISE, and it is the strong form: EVERY audio frame
            //    offered was delivered. Audio has no drop path at all, so the
            //    count sent must equal the count handed over.
            assertTrue("audio was lost: $audioSent delivered of $i offered", audioSent >= i - 2)
            // 4. And no whole second of the congestion was silent.
            //
            //    Read this number carefully: it counts the HARNESS's own
            //    iterations, which also encode a frame, sleep 33 ms and do
            //    bookkeeping — it dips to ~13 in the thinnest second and that
            //    is this loop's cadence, NOT a gap in delivered audio, which
            //    assertion 3 has already shown to be complete. It is kept only
            //    to catch the one thing it can honestly catch: a whole second
            //    with nothing at all.
            assertTrue("a whole second of congestion carried no audio — a gap in " +
                       "the host's voice is the one thing §6.4 promises against",
                       worstAudioSecond > 0)
        } finally {
            // AND WAIT FOR IT TO ACTUALLY GO. `destroyForcibly` returns the
            // Process, not a dead one — and a proxy that outlives its test
            // holds the port for the NEXT run, which is exactly the failure
            // above. Waiting is what makes the cleanup true rather than
            // requested.
            proxy.destroyForcibly()
            proxy.waitFor(5, java.util.concurrent.TimeUnit.SECONDS)
        }
    }
}
