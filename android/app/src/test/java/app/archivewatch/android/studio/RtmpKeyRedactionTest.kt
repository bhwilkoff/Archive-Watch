package app.archivewatch.android.studio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** §8.68's Android half: a server that quotes the key back does not print it. */
class RtmpKeyRedactionTest {
    private val key = "abcd-1234-efgh-5678"

    @Test fun `an echoed key is redacted and the sentence survives`() {
        val out = redactKey("NetStream.Publish.BadName: $key already publishing", key)
        assertFalse(out.contains(key))
        assertTrue(out.contains("already publishing"))
    }

    @Test fun `the percent-encoded form is redacted`() {
        assertFalse(redactKey("live/abcd%201234 not found", "abcd 1234").contains("abcd%201234"))
    }

    @Test fun `a short key is left alone`() {
        assertEquals("the live stream", redactKey("the live stream", "live"))
    }
}
