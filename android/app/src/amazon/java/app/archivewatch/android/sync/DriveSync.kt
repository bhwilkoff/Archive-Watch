package app.archivewatch.android.sync

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.content.IntentSender
import app.archivewatch.android.data.UserStateStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

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

    data class Status(
        val signedIn: Boolean = false,
        val account: String? = null,
        val lastSyncAt: Long = 0,
        val lastError: String? = null,
        val syncing: Boolean = false,
    )
    private val _status = MutableStateFlow(Status())
    val status: StateFlow<Status> = _status

    fun attach(application: Application, userState: UserStateStore, appScope: CoroutineScope) {}
    fun signIn(activity: Activity, launchConsent: (IntentSender) -> Unit) {}
    fun onConsentResult(activity: Activity, data: Intent?) {}
    fun signIn(activity: Activity, userState: UserStateStore, onDone: (Boolean) -> Unit) {
        onDone(false)
    }
    fun signOut() {}
    fun syncNow() {}
    fun syncNow(userState: UserStateStore, onDone: (Boolean) -> Unit) { onDone(false) }
}
