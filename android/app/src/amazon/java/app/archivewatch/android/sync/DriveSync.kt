package app.archivewatch.android.sync

import android.app.Activity
import app.archivewatch.android.data.UserStateStore

/**
 * Drive App Data sync — **amazon flavor: permanently absent**.
 *
 * Fire OS has no Google Play Services, so Google sign-in and the Drive
 * appDataFolder cannot exist on this variant (same structural split as
 * CastSupport, Decision 047). The google-flavor twin carries the real
 * implementation; identical signatures keep call sites store-blind.
 */
object DriveSync {
    const val IS_SUPPORTED: Boolean = false
    val isConfigured: Boolean get() = false
    val isSignedIn: Boolean get() = false
    val lastSyncAt: Long get() = 0

    fun signIn(activity: Activity, userState: UserStateStore, onDone: (Boolean) -> Unit) {
        onDone(false)
    }
    fun signOut() {}
    fun syncNow(userState: UserStateStore, onDone: (Boolean) -> Unit) { onDone(false) }
}
