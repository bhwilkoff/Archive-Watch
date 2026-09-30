package app.archivewatch.android.studio

// Where a platform token lives on Android (docs/WATCH-TOGETHER.md §6.1).
//
// §6.1 says tokens live in the platform's own protected store, are never
// synchronised, and never reach disk in plaintext. On Apple that is the
// Keychain with `…AfterFirstUnlockThisDeviceOnly`; here it is a SecretStore
// (AES-256-GCM, a key the Android Keystore holds; it replaced the deprecated
// EncryptedSharedPreferences on 2026-09-29), which is
// the same promise made by the same kind of mechanism: the key is hardware
// backed where the device has a StrongBox or TEE, and it cannot leave the
// device at all.
//
// TWO THINGS ARE DELIBERATE, and both are the Android half of a defect found
// on macOS the same day (§9.aaaa — a token written with a flag the platform
// silently ignored):
//
//  1. The manifest already carries `android:allowBackup="false"`, so these
//     preferences are not in any Drive backup. That was CHECKED, not assumed —
//     an encrypted preference file whose Keystore key cannot be restored would
//     come back undecryptable rather than leak, but "it would fail safely" is
//     not the same promise as "it is never copied".
//  2. `clear` removes the entry rather than writing an empty one, so a signed
//     out host leaves nothing behind that a later read could mistake for a
//     session.

import android.content.Context
import app.archivewatch.android.data.LegacyEncryptedPrefs
import app.archivewatch.android.data.SecretStore
import org.json.JSONObject

data class StudioToken(
    val access: String,
    val refresh: String?,
    val expiresAtMillis: Long?,
) {
    /// A minute of slack: a token that expires mid-handshake is worse than one
    /// refreshed slightly early. Same rule as the Swift store.
    val isFresh: Boolean
        get() = expiresAtMillis?.let { it - System.currentTimeMillis() > 60_000 } ?: true
}

object StudioTokenStore {
    private const val FILE = "studio_oauth_v2"
    private const val LEGACY_FILE = "studio_oauth"

    @Volatile private var migrated = false

    /**
     * The store, after moving any tokens out of the old EncryptedSharedPreferences
     * file once. An old file that will not decrypt (it outlived its Keystore key)
     * is simply dropped: a token nobody can read is worth nothing, and signing
     * in again is the cost — the rule this store already had.
     */
    private fun store(context: Context): SecretStore {
        val s = SecretStore(context, FILE)
        if (!migrated) {
            migrated = true
            val legacy = LegacyEncryptedPrefs.readAll(context, LEGACY_FILE)
            if (legacy.isNotEmpty() && s.isEmpty()) s.putStrings(legacy, commit = true)
            LegacyEncryptedPrefs.delete(context, LEGACY_FILE)
        }
        return s
    }

    /// Returns whether the write actually landed.
    ///
    /// The Swift store returns the Keychain's own OSStatus for one reason
    /// (§9.rrr): Twitch's refresh tokens are ONE-TIME-USE, so by the time the
    /// store is asked to keep a renewed token the old one is already dead, and
    /// a dropped failure there signs the host out permanently with nothing to
    /// diagnose. `commit()` rather than `apply()` for the same reason — the
    /// caller must be able to find out.
    fun save(context: Context, platform: String, token: StudioToken): Boolean = runCatching {
        val o = JSONObject()
            .put("access", token.access)
            .put("refresh", token.refresh ?: JSONObject.NULL)
            .put("expires", token.expiresAtMillis ?: JSONObject.NULL)
        // commit's Boolean is the answer: a one-time refresh token that did not land is lost.
        store(context).putStrings(mapOf(platform to o.toString()), commit = true)
    }.getOrDefault(false)

    fun load(context: Context, platform: String): StudioToken? = runCatching {
        val raw = store(context).getString(platform) ?: return null
        val o = JSONObject(raw)
        StudioToken(
            access = o.getString("access"),
            refresh = o.optString("refresh").ifEmpty { null },
            expiresAtMillis = if (o.isNull("expires")) null else o.getLong("expires"),
        )
    }.getOrNull()

    fun clear(context: Context, platform: String) {
        runCatching { store(context).remove(platform, commit = true) }
    }

    fun isSignedIn(context: Context, platform: String): Boolean = load(context, platform) != null
}
