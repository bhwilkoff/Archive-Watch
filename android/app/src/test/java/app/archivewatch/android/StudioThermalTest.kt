package app.archivewatch.android

import app.archivewatch.android.studio.StudioEngine
import app.archivewatch.android.studio.ThermalAction
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * WATCH-TOGETHER §6.5 on Android: the decision, checked against the rule.
 *
 * The rule had been written for weeks and implemented nowhere on either
 * platform, and on Apple it was also factually WRONG — it asked for a
 * resolution change, which an RTMP ingest will not take mid-publish. So the
 * decision is worth testing separately from the wiring: the loop that applies
 * it needs a GL context and a MediaCodec, which means it can only ever run on
 * a device, and "it ran" is not "it was right".
 *
 * Statuses are PowerManager's: NONE 0, LIGHT 1, MODERATE 2, SEVERE 3,
 * CRITICAL 4, EMERGENCY 5, SHUTDOWN 6.
 */
class StudioThermalTest {

    private val configured = 4_000_000
    private val stepped = StudioEngine.steppedBitrate(configured)

    private fun action(status: Int, current: Int = configured) =
        StudioEngine.thermalAction(status, current, configured)

    @Test fun `severe steps the bitrate down`() {
        assertEquals(ThermalAction.STEP_DOWN, action(StudioEngine.THERMAL_SEVERE))
        assertEquals("60% of the configured rate", 2_400_000, stepped)
    }

    @Test fun `the step is idempotent`() {
        // Already stepped: re-applying every second would be a pointless
        // setParameters call and a repeated note to the host.
        assertEquals(ThermalAction.NONE, action(StudioEngine.THERMAL_SEVERE, current = stepped))
    }

    @Test fun `cool states restore, but only when something was stepped`() {
        for (s in 0..2) {
            assertEquals("status $s should restore a stepped stream",
                         ThermalAction.RESTORE, action(s, current = stepped))
            assertEquals("status $s should do nothing to an unstepped stream",
                         ThermalAction.NONE, action(s, current = configured))
        }
    }

    @Test fun `critical and everything above it ENDS the show`() {
        // Not a quality step: above SEVERE the platform itself starts stopping
        // things, so the show ends with a reason rather than freezing.
        for (s in StudioEngine.THERMAL_CRITICAL..6) {
            assertEquals("status $s must end the show", ThermalAction.END_SHOW, action(s))
        }
    }

    @Test fun `an unknown future status above critical still ends the show`() {
        // A platform that adds a state worse than SHUTDOWN must not read as
        // "nothing to do" — the comparison is >=, deliberately.
        assertEquals(ThermalAction.END_SHOW, action(99))
    }

    @Test fun `severe never ends the show`() {
        // The one boundary worth pinning: SEVERE degrades, it does not stop.
        // A broadcast that ends because a phone got warm is a worse bug than a
        // lower bitrate.
        assertEquals(ThermalAction.STEP_DOWN, action(3))
    }
}
