package app.archivewatch.android.studio

// Where a platform token lives on Android (docs/WATCH-TOGETHER.md §6.1).
//
// §6.1 says tokens live in the platform's own protected store, are never
// synchronised, and never reach disk in plaintext. On Apple that is the
// Keychain with `…AfterFirstUnlockThisDeviceOnly`; here it is
// EncryptedSharedPreferences over a key the Android Keystore holds, which is
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
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
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
    private const val FILE = "studio_oauth"

    private fun prefs(context: Context): SharedPreferences {
        val key = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            context, FILE, key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
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
        prefs(context).edit().putString(platform, o.toString()).commit()
    }.getOrDefault(false)

    fun load(context: Context, platform: String): StudioToken? = runCatching {
        val raw = prefs(context).getString(platform, null) ?: return null
        val o = JSONObject(raw)
        StudioToken(
            access = o.getString("access"),
            refresh = o.optString("refresh").ifEmpty { null },
            expiresAtMillis = if (o.isNull("expires")) null else o.getLong("expires"),
        )
    }.getOrNull()

    fun clear(context: Context, platform: String) {
        runCatching { prefs(context).edit().remove(platform).commit() }
    }

    fun isSignedIn(context: Context, platform: String): Boolean = load(context, platform) != null
}
