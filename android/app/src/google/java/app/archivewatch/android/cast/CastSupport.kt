package app.archivewatch.android.cast

import android.content.Context
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastState
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability

/**
 * Cast support — **google flavor**.
 *
 * The amazon-flavor twin of this file has the identical signature and returns
 * "unsupported" for everything, so call sites never branch on store
 * (docs/TV-DESIGN.md §6.6, Decision 047).
 *
 * Even here, GMS presence is checked at runtime rather than assumed: a Play
 * build can legitimately land on a device with Play Services missing, stale, or
 * disabled, and `CastContext.getSharedInstance` throws in that case. Casting is
 * a bonus route to the TV — it must never be able to take the app down.
 */
object CastSupport {

    const val IS_SUPPORTED: Boolean = true

    @Volatile
    private var context: CastContext? = null

    /**
     * Initialize lazily and defensively. Safe to call more than once, and safe
     * to call on a device with no usable Play Services.
     */
    fun initialize(appContext: Context) {
        if (context != null) return
        val gms = GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(appContext)
        if (gms != ConnectionResult.SUCCESS) return
        context = runCatching { CastContext.getSharedInstance(appContext) }.getOrNull()
    }

    /** True once a receiver device is discoverable or connected. */
    fun isCastAvailable(): Boolean {
        val state = context?.castState ?: return false
        return state != CastState.NO_DEVICES_AVAILABLE
    }
}
