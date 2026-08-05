package app.archivewatch.android.cast

import android.content.Context

/**
 * Cast support — **amazon flavor: permanently absent**.
 *
 * Fire OS ships without Google Play Services, so the Cast SDK cannot be linked
 * into this variant at all. This is a structural split rather than a runtime
 * guard because the failure mode is a RUNTIME crash on a real Fire TV device,
 * not a build error — a code-level `if (hasGms)` would still pull the classes
 * into the APK (docs/TV-DESIGN.md §6.6, Decision 047).
 *
 * The google-flavor twin of this file has the identical signature, so every
 * call site is flavor-agnostic and nothing outside this package branches on
 * store.
 *
 * ⚠️ Do not add a GMS dependency to reach parity here. Fire TV's route to a
 * second screen is the device's own mirroring, not Cast.
 */
object CastSupport {

    /** Always false on Fire OS — there is no Cast framework to talk to. */
    const val IS_SUPPORTED: Boolean = false

    /** No-op: nothing to initialize. */
    fun initialize(context: Context) = Unit

    /** No devices are ever discoverable from this variant. */
    fun isCastAvailable(): Boolean = false
}
