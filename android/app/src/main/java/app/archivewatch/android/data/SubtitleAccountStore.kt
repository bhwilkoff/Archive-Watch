package app.archivewatch.android.data

import android.content.Context

/**
 * The viewer's OpenSubtitles credentials — a third-party CONTENT credential,
 * not an identity (the iOS SubtitleAccount, ported). A [SecretStore] (Keystore
 * AES-256-GCM) is the Keychain analogue; nothing here ever touches plain prefs or the
 * catalog. Sign-in is optional and gates only subtitle search.
 */
class SubtitleAccountStore(context: Context) {

    // LAZY: the Keystore key costs real time on a weak TV SoC the first time,
    // and it used to be built in Application.onCreate — before Home could
    // draw — for a feature only reached from Settings.
    private val store: SecretStore by lazy {
        val st = SecretStore(context, "aw.opensubtitles.v2")
        // Once: move the credentials out of the deprecated EncryptedSharedPreferences
        // file (or the plain fallback it used when the Keystore refused).
        val legacy = LegacyEncryptedPrefs.readAll(context, "aw.opensubtitles").ifEmpty {
            context.getSharedPreferences("aw.opensubtitles.fallback", Context.MODE_PRIVATE)
                .all.mapNotNull { (k, v) -> v?.let { k to it.toString() } }.toMap()
        }
        if (legacy.isNotEmpty() && st.isEmpty()) st.putStrings(legacy, commit = true)
        LegacyEncryptedPrefs.delete(context, "aw.opensubtitles")
        LegacyEncryptedPrefs.delete(context, "aw.opensubtitles.fallback")
        st
    }

    @Volatile private var session: OpenSubtitlesClient.Session? = null

    val username: String? get() = store.getString("username")
    val isConnected: Boolean get() = username != null
    val quotaAllowed: Int get() = store.getString("quotaAllowed")?.toIntOrNull() ?: 0
    val quotaRemaining: Int get() = store.getString("quotaRemaining")?.toIntOrNull() ?: 0

    /** Validates by logging in; stores credentials only on success. */
    suspend fun connect(username: String, password: String) {
        val s = OpenSubtitlesClient.login(username.trim(), password)
        session = s
        store.putStrings(mapOf(
            "username" to username.trim(),
            "password" to password,
            "quotaAllowed" to (s.quota?.allowed ?: 0).toString(),
            "quotaRemaining" to (s.quota?.remaining ?: 0).toString(),
        ))
    }

    fun disconnect() {
        session = null
        store.clear()
    }

    /** A fresh-enough token, re-logging in at most every ~20h (never per fetch). */
    suspend fun token(): String {
        session?.takeIf { it.isFresh }?.let { return it.token }
        val u = username ?: throw OpenSubtitlesClient.SubsException(
            "Connect your OpenSubtitles account in Settings.")
        val p = store.getString("password") ?: throw OpenSubtitlesClient.SubsException(
            "Connect your OpenSubtitles account in Settings.")
        val s = OpenSubtitlesClient.login(u, p)
        session = s
        s.quota?.let {
            store.putStrings(mapOf(
                "quotaAllowed" to it.allowed.toString(),
                "quotaRemaining" to it.remaining.toString(),
            ))
        }
        return s.token
    }
}
