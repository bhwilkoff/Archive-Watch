package app.archivewatch.android.studio

import android.content.Context
import android.content.pm.PackageManager

/**
 * Can this device HOST a Watch Together broadcast?
 *
 * Owner, 2026-09-20: *"There is no reason to build/have a feature that shows
 * as 'watch together' with only the ability to stream from the
 * Android/google/fire tv box without a camera and microphone to go along with
 * it. Everyone might as well just watch the movie on their own. The point of
 * watching together is to stream the video and have the ability to provide
 * commentary or conversation on top of it."*
 *
 * So the gate is not "can this device encode" — every box can. It is **can a
 * host be present in the show**, which needs a camera and a microphone. A
 * television box has neither and cannot borrow them: Continuity Camera is an
 * Apple arrangement, and that is exactly why tvOS keeps its entry while
 * Google TV and Fire TV lose theirs.
 *
 * Decision 131 says a device states which of the three Watch Together modes
 * it can do rather than showing a missing button. A device that can NEVER do
 * one omits it entirely — there is nothing for a host to act on, and a
 * permanent apology on a Detail screen is clutter, not information. The
 * explanation lives in PARITY's table, which is where someone asks the
 * question.
 */
object StudioCapability {

    /** The decision, as a pure function, so it can be tested without a device. */
    fun canHostShow(hasCamera: Boolean, hasMicrophone: Boolean): Boolean =
        hasCamera && hasMicrophone
}

/**
 * FEATURE_CAMERA_ANY, not FEATURE_CAMERA: the latter means a REAR camera, and
 * a front-facing-only device is exactly the shape that should pass here.
 */
fun Context.canHostWatchTogether(): Boolean =
    StudioCapability.canHostShow(
        hasCamera = packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY),
        hasMicrophone = packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE),
    )
