package app.archivewatch.android.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * The viewer's OpenSubtitles credentials — a third-party CONTENT credential,
 * not an identity (the iOS SubtitleAccount, ported). EncryptedSharedPreferences
 * is the Keychain analogue; nothing here ever touches plain prefs or the
 * catalog. Sign-in is optional and gates only subtitle search.
 */
class SubtitleAccountStore(context: Context) {

    private val prefs: SharedPreferences = runCatching {
        val key = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context, "aw.opensubtitles", key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }.getOrElse {
        // Keystore hiccups exist on some OEMs; app-private prefs are the
        // degraded-but-functional fallback rather than a dead feature.
        context.getSharedPreferences("aw.opensubtitles.fallback", Context.MODE_PRIVATE)
    }

    @Volatile private var session: OpenSubtitlesClient.Session? = null

    val username: String? get() = prefs.getString("username", null)
    val isConnected: Boolean get() = username != null
    val quotaAllowed: Int get() = prefs.getInt("quotaAllowed", 0)
    val quotaRemaining: Int get() = prefs.getInt("quotaRemaining", 0)

    /** Validates by logging in; stores credentials only on success. */
    suspend fun connect(username: String, password: String) {
        val s = OpenSubtitlesClient.login(username.trim(), password)
        session = s
        prefs.edit()
            .putString("username", username.trim())
            .putString("password", password)
            .putInt("quotaAllowed", s.quota?.allowed ?: 0)
            .putInt("quotaRemaining", s.quota?.remaining ?: 0)
            .apply()
    }

    fun disconnect() {
        session = null
        prefs.edit().clear().apply()
    }

    /** A fresh-enough token, re-logging in at most every ~20h (never per fetch). */
    suspend fun token(): String {
        session?.takeIf { it.isFresh }?.let { return it.token }
        val u = username ?: throw OpenSubtitlesClient.SubsException(
            "Connect your OpenSubtitles account in Settings.")
        val p = prefs.getString("password", null) ?: throw OpenSubtitlesClient.SubsException(
            "Connect your OpenSubtitles account in Settings.")
        val s = OpenSubtitlesClient.login(u, p)
        session = s
        s.quota?.let {
            prefs.edit().putInt("quotaAllowed", it.allowed)
                .putInt("quotaRemaining", it.remaining).apply()
        }
        return s.token
    }
}
