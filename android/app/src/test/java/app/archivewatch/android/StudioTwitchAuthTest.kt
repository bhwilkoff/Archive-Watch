package app.archivewatch.android

import app.archivewatch.android.studio.StudioPlatformAuth
import app.archivewatch.android.studio.StudioPlatformAuth.PollOutcome
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.HttpURLConnection
import java.net.URL

/**
 * Twitch sign-in on Android: the RULES the product runs, and the REFUSALS the
 * live endpoints actually return.
 *
 * Mirrors the Swift §8.9 case. Two halves, and both matter:
 *
 *  - The pure rule (`pollOutcome`) is asserted against the exact strings
 *    measured from Twitch, by calling the PRODUCT's function rather than
 *    re-implementing it. Decision 119: a check that restates the logic proves
 *    only that it was copied twice.
 *  - The endpoint shapes are asserted with no credential at all, because what
 *    is being asserted is how REFUSALS read. Decision 128: prove the request
 *    shapes before the credentials exist.
 */
class StudioTwitchAuthTest {

    // ---- the rule, against strings measured from the live endpoint ----

    @Test fun unconfirmedPollKeepsWaiting() {
        assertTrue(StudioPlatformAuth.pollOutcome("authorization_pending") is PollOutcome.KeepWaiting)
    }

    @Test fun deadDeviceCodeIsRefused() {
        // Twitch answers HTTP 400 for BOTH of these, so the status carries no
        // information; this is the whole reason the message is the input.
        assertTrue(StudioPlatformAuth.pollOutcome("invalid device code") is PollOutcome.Refused)
    }

    @Test fun slowDownBacksOff() {
        assertTrue(StudioPlatformAuth.pollOutcome("slow_down") is PollOutcome.BackOff)
    }

    @Test fun anUnREADABLEanswerWaitsRatherThanEndingTheSignIn() {
        // A message we do not recognise must not end a sign-in that might still
        // succeed — the failure mode of `!message.contains("pending")`.
        assertTrue(StudioPlatformAuth.pollOutcome("") is PollOutcome.KeepWaiting)
    }

    // ---- the endpoints, with no credential ----

    private fun validateMessage(header: String?): Pair<Int, String> {
        val c = URL("https://id.twitch.tv/oauth2/validate").openConnection() as HttpURLConnection
        header?.let { c.setRequestProperty("Authorization", it) }
        val code = c.responseCode
        val body = (c.errorStream ?: c.inputStream).bufferedReader().readText()
        c.disconnect()
        return code to JSONObject(body).optString("message")
    }

    @Test fun validateSeparatesABadTokenFromAMissingOne() {
        val (badCode, bad) = validateMessage("OAuth not-a-real-token")
        val (missCode, missing) = validateMessage(null)

        assertEquals("a bad token is a 401", 401, badCode)
        assertEquals("a missing header is ALSO a 401", 401, missCode)
        // THE CONTROL. Identical statuses, so if the messages matched too the
        // product could not tell a host "sign in again" from a bug in its own
        // request.
        assertNotEquals("the status cannot discriminate; the message must", bad, missing)
        assertTrue(bad.contains("invalid access token"))
        assertTrue(missing.contains("missing authorization token"))
    }

    @Test fun theDeviceEndpointRefusesAnUnknownClient() {
        val c = URL("https://id.twitch.tv/oauth2/device").openConnection() as HttpURLConnection
        c.requestMethod = "POST"
        c.doOutput = true
        c.outputStream.write("client_id=not-a-real-client&scopes=channel:manage:broadcast".toByteArray())
        // `responseCode` FIRST. Reading `inputStream` on a 4xx throws IOException,
        // and `errorStream` is null until the response has been read — so the
        // obvious `errorStream ?: inputStream` throws instead of returning the
        // refusal this test is about. The first version failed on exactly that
        // and said nothing about Twitch.
        c.responseCode
        val body = (c.errorStream ?: c.inputStream).bufferedReader().readText()
        c.disconnect()
        // It must REFUSE, and it must not hand back a device code we could then
        // show a host and poll on forever.
        assertTrue("an unknown client must not be issued a device code",
            !JSONObject(body).has("device_code"))
    }
}
