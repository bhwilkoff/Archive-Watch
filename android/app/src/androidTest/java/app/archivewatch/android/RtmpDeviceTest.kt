package app.archivewatch.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import app.archivewatch.android.studio.RtmpPublisher
import app.archivewatch.android.studio.RtmpStreamConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.InetSocketAddress
import java.net.Socket

/**
 * The publisher on REAL ANDROID HARDWARE (docs/DEVICE-TESTING.md: real devices,
 * never emulators).
 *
 * The JVM unit test proves the protocol; this proves it survives a device's
 * actual network stack, TLS provider and socket timing — which is a different
 * question, and the one that has bitten this project before (a LocalMediaServer
 * passed every Mac gate and failed on the device, Decision 082).
 *
 * The server is the developer Mac, so the address is passed in rather than
 * assumed:
 *
 *   ./gradlew :app:connectedGoogleDebugAndroidTest \
 *     -Pandroid.testInstrumentationRunnerArguments.rtmpHost=10.0.0.90
 *
 * It SKIPS when no server is reachable — a red result must mean the publisher
 * is broken, never that a laptop was asleep (Decision 107).
 */
@RunWith(AndroidJUnit4::class)
class RtmpDeviceTest {

    private val host: String =
        androidx.test.platform.app.InstrumentationRegistry.getArguments()
            .getString("rtmpHost") ?: "10.0.0.90"
    private val port = 19351

    private fun serverIsUp(): Boolean = try {
        Socket().use { it.connect(InetSocketAddress(host, port), 1500); true }
    } catch (_: Exception) { false }

    @Test fun publishesFromTheDevice() {
        assumeTrue("no RTMP server at $host:$port — skipping", serverIsUp())
        val p = RtmpPublisher()
        p.publish(
            "rtmp://$host:$port/live", "devicetest",
            RtmpStreamConfig(
                width = 1920, height = 1080, frameRate = 30.0, videoBitrate = 6_000_000,
                avcC = RealH264.avcC,
                audioSampleRate = 44100, audioChannels = 1, audioBitrate = 128_000,
                audioSpecificConfig = RealAac.asc
            )
        )
        assertEquals("publishing", p.health.state)
        assertTrue("the server never acknowledged connect", p.health.connectAcknowledged)

        // Enough media for the server to commit to a path — a short burst
        // measures the length of the burst, not the publisher (§6.2a).
        for (i in 0 until 300) {
            p.sendVideo(RealH264.idrAvcc, isKeyframe = true, ptsMs = i * 33, dtsMs = i * 33)
            p.sendAudio(RealAac.frame, ptsMs = i * 23)
        }
        assertEquals(300L, p.health.videoFramesSent)
        assertTrue("nothing reached the wire", p.health.bytesSent > 100_000)
        assertEquals("the connection did not survive the burst", "publishing", p.health.state)
        Thread.sleep(2000)   // let the server register before we hang up
        p.close()
    }
}
