package app.archivewatch.android.data

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.content.edit
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * A small string store whose VALUES are sealed with an AES-256-GCM key that
 * lives in the Android Keystore and never leaves it: each value is saved as
 * base64(12-byte IV + ciphertext) in ordinary app-private preferences.
 *
 * It replaces androidx.security's EncryptedSharedPreferences, which the
 * library deprecated in 1.1.0 with no further releases; Google's guidance is
 * the Keystore directly (KeyGenParameterSpec + Cipher). Keystore AES/GCM
 * exists from API 23, the app's floor (Decision 141), so there is no fallback
 * branch. Keys are not secret here (they are fixed names); values are.
 *
 * A value that will not decrypt — the file outlived its Keystore key through a
 * restore or a transfer to another phone — reads as absent, and the owner of
 * the store asks for a fresh sign-in, as the old stores did.
 */
class SecretStore(context: Context, file: String) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(file, Context.MODE_PRIVATE)

    fun getString(name: String): String? = prefs.getString(name, null)?.let(::open)

    fun contains(name: String): Boolean = prefs.contains(name)

    fun isEmpty(): Boolean = prefs.all.isEmpty()

    /** Sealed and written; [commit] = true returns whether it reached disk. */
    @Suppress("UseKtx") // commit's Boolean is the point: a caller must learn a write was lost
    fun putStrings(values: Map<String, String?>, commit: Boolean = false): Boolean {
        val e = prefs.edit()
        for ((k, v) in values) {
            if (v == null) { e.remove(k); continue }
            val sealed = seal(v) ?: return false
            e.putString(k, sealed)
        }
        return if (commit) e.commit() else { e.apply(); true }
    }

    fun remove(name: String, commit: Boolean = false) = prefs.edit(commit = commit) { remove(name) }

    fun clear(commit: Boolean = false) = prefs.edit(commit = commit) { clear() }

    private fun seal(plain: String): String? = runCatching {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val body = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        Base64.encodeToString(cipher.iv + body, Base64.NO_WRAP)
    }.onFailure { android.util.Log.w("AWSECRET", "seal failed: $it") }.getOrNull()

    private fun open(sealed: String): String? = runCatching {
        val bytes = Base64.decode(sealed, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, bytes, 0, IV_BYTES))
        String(cipher.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES), Charsets.UTF_8)
    }.onFailure { android.util.Log.w("AWSECRET", "open failed: $it") }.getOrNull()

    private companion object {
        const val KEY_ALIAS = "archivewatch.secrets"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128

        @Synchronized
        fun key(): SecretKey {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
            val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            gen.init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build(),
            )
            return gen.generateKey()
        }
    }
}
