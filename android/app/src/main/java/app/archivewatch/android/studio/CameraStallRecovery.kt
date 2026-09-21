package app.archivewatch.android.studio

/**
 * Should a camera that stopped delivering be re-attached?
 *
 * A PORT of Swift's `CameraStallRecovery`, thresholds and all, so the three
 * platforms that can carry a host camera agree on what a stall IS. Android had
 * no guard at all — reasonably, until 2026-09-20, because until that morning
 * Android had no camera to stall. Now it does, and a phone's camera stops
 * whenever a call arrives, which makes this a phone's problem more than a
 * television's.
 *
 * A pure value type so the rule can be tested without a camera or a show —
 * `StudioCameraStallTest` asserts the same nine cases §8.23 does.
 */
class CameraStallRecovery {

    var stallTicks = 0
        private set
    var attempts = 0
        private set

    /** Feed one health tick. True when the caller should re-attach. */
    fun tick(attached: Boolean, framesReceived: Long,
             framesPerSecond: Int, onAir: Boolean): Boolean {
        // ONLY A CAMERA THAT HAD STARTED. One that never delivered a frame is
        // a different problem with a different sentence, and re-attaching it
        // in a loop would hide that — on Android especially, where a
        // television has no camera at all and would otherwise rebuild three
        // times every show.
        if (!attached || framesReceived <= 0L || !onAir || framesPerSecond != 0) {
            if (framesPerSecond > 0) stallTicks = 0
            return false
        }
        stallTicks++
        if (stallTicks < TICKS_BEFORE_RECOVERY || attempts >= MAX_ATTEMPTS) return false
        stallTicks = 0
        attempts++
        return true
    }

    fun reset() { stallTicks = 0; attempts = 0 }

    companion object {
        /** Four seconds: a camera legitimately misses a tick. */
        const val TICKS_BEFORE_RECOVERY = 4
        /** Three, then stop asking. */
        const val MAX_ATTEMPTS = 3
    }
}
