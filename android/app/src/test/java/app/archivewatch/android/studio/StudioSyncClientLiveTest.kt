package app.archivewatch.android.studio

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.net.HttpURLConnection
import java.net.URL

/**
 * §8.33 — the ANDROID client against a running Worker.
 *
 * `StudioSyncTest` proves the arithmetic and the Swift §8.31 proves the
 * routes agree with a Swift client. Neither says THIS client speaks to that
 * server correctly, which is Decision 133 again: a control is proved where
 * its value lands.
 *
 * Skips when no local Worker is answering — and a skip here is not a pass, it
 * is Android's transport going unexercised. Start one with:
 *
 *     cd worker && npx wrangler d1 execute archivewatch-pulse --local \
 *       --file=schema-rooms.sql && npx wrangler dev --local --port 8799
 */
class StudioSyncClientLiveTest {

    private val base = System.getenv("AW_TOGETHER_BASE") ?: "http://127.0.0.1:8799"

    private fun workerIsUp(): Boolean = runCatching {
        val c = (URL("$base/together/ABCD").openConnection() as HttpURLConnection).apply {
            connectTimeout = 1500; readTimeout = 1500
        }
        try { c.responseCode in 200..499 } finally { c.disconnect() }
    }.getOrDefault(false)

    @Test fun `a host opens a room and a guest follows it`() = runBlocking {
        assumeTrue("no Worker on $base — this is a SKIP, not a pass", workerIsUp())

        val film = "ptp_the-love-nest_buster-keaton_blu-ray_h264_1080p_430833"
        val host = StudioSyncClient(base)
        val guest = StudioSyncClient(base)

        val code = host.createRoom(film, position = 60.0)
        assertEquals(StudioRoom.CODE_LENGTH, code.length)

        // Join by the code AS HEARD, not as generated — the 1s and 0s retyped
        // as I and O, which is the whole reason normalize exists.
        val heard = code.replace('1', 'I').replace('0', 'O').lowercase()
        val joined = guest.join(heard)
        assertEquals("a code typed as heard reaches the same room", film, joined.filmID)
        assertEquals(60.0, joined.position, 1e-6)

        val off = guest.clockOffset
        assertNotNull("the guest has a clock offset", off)
        assertTrue("against a local Worker the bound is tight", off!!.second < 0.5)

        val expected = joined.expectedPosition(guest.serverNow())
        assertEquals(StudioSync.Correction.None, guest.correction(expected, false))
        assertEquals(
            StudioSync.Correction.Nudge(StudioSync.NUDGE_FAST),
            guest.correction(expected - 1.0, false),
        )

        // THE END TO END CLAIM: the host pauses and the guest's player is told
        // to pause. Nothing else asserts that publish, poll and arithmetic
        // agree across the wire.
        host.publish(film, position = 75.0, paused = true)
        guest.poll()
        assertEquals(
            StudioSync.Correction.SetPaused(true),
            guest.correction(expected, false),
        )
        assertEquals(75.0, guest.lastState!!.position, 1e-6)

        // CONTROL: resuming must reverse it, or SetPaused could be a one-way
        // latch that happens to read true.
        host.publish(film, position = 80.0, paused = false)
        guest.poll()
        assertEquals(
            StudioSync.Correction.SetPaused(false),
            guest.correction(80.0, true),
        )

        host.endRoom()
        val gone = runCatching { guest.poll() }.exceptionOrNull()
        assertTrue("a guest polling an ended room is told so", gone is StudioSyncClient.JoinError)
    }

    @Test fun `a guest with only the code cannot drive the show`() = runBlocking {
        assumeTrue("no Worker on $base — this is a SKIP, not a pass", workerIsUp())
        val host = StudioSyncClient(base)
        val code = host.createRoom("x", position = 10.0)

        // A client that only JOINED holds no host key (§11.12), so its write
        // must be refused — that is the whole property.
        val guest = StudioSyncClient(base)
        guest.join(code)
        val refused = runCatching { guest.publish("x", position = 999.0) }.exceptionOrNull()
        assertTrue("a guest write must be refused", refused != null)

        guest.poll()
        assertEquals("and the room must be unchanged", 10.0, guest.lastState!!.position, 1e-6)
        host.endRoom()
    }
}
