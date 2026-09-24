package app.archivewatch.android

import app.archivewatch.android.studio.StudioPlatformAuth
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** §8.64's Android half: hourly, and only a 401 revokes. */
class StudioTwitchValidateTest {
    @Test fun dueFirstThenHourly() {
        assertTrue(StudioPlatformAuth.validationDue(0L, 5_000L))
        assertFalse(StudioPlatformAuth.validationDue(1_000L, 1_000L + 3_599_000L))
        assertTrue(StudioPlatformAuth.validationDue(1_000L, 1_000L + 3_600_000L))
    }

    @Test fun onlyA401Revokes() {
        assertTrue(StudioPlatformAuth.validationRevokes(401))
        assertFalse(StudioPlatformAuth.validationRevokes(null))
        assertFalse(StudioPlatformAuth.validationRevokes(503))
        assertFalse(StudioPlatformAuth.validationRevokes(200))
    }

    @Test fun onlyTwitchsOwnAnswerClearsOnRefresh() {
        assertTrue(StudioPlatformAuth.refreshWasRevoked(400, "Invalid refresh token"))
        assertFalse(StudioPlatformAuth.refreshWasRevoked(500, "Invalid refresh token"))
        assertFalse(StudioPlatformAuth.refreshWasRevoked(400, "missing client id"))
    }

    @Test fun noChatScopeRequested() {
        assertFalse("user:read:chat" in StudioPlatformAuth.twitchScopes)
    }
}
