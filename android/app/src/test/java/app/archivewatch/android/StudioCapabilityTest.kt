package app.archivewatch.android

import app.archivewatch.android.studio.StudioCapability
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Owner 2026-09-20: a broadcast with no camera and no microphone is not
 * watching together. The gate is that the HOST can be in the show, which is
 * why a television box loses the entry and a phone keeps it.
 */
class StudioCapabilityTest {

    @Test fun `a phone with both can host`() {
        assertTrue(StudioCapability.canHostShow(hasCamera = true, hasMicrophone = true))
    }

    @Test fun `a television box with neither cannot host`() {
        assertFalse(StudioCapability.canHostShow(hasCamera = false, hasMicrophone = false))
    }

    // The two halves are asserted SEPARATELY, because "&&" written as "||" passes
    // the both-true and both-false cases and fails only these.
    @Test fun `a camera with no microphone cannot host — silence is not commentary`() {
        assertFalse(StudioCapability.canHostShow(hasCamera = true, hasMicrophone = false))
    }

    @Test fun `a microphone with no camera cannot host`() {
        assertFalse(StudioCapability.canHostShow(hasCamera = false, hasMicrophone = true))
    }
}
