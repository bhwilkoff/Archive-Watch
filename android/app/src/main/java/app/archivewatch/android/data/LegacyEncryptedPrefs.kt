package app.archivewatch.android.data

import android.content.Context
import android.os.Build

/**
 * Reads a file written by androidx.security's EncryptedSharedPreferences, once,
 * so its contents can move into a [SecretStore]. That library is deprecated
 * (1.1.0, no further releases); this object is the only code left that touches
 * it, and it goes — with the security-crypto dependency — once no install can
 * still hold an old file.
 */
@Suppress("DEPRECATION") // reading the deprecated format is this object's whole job
object LegacyEncryptedPrefs {

    /** Every entry as a string, or empty when there is no file or it will not decrypt. */
    fun readAll(context: Context, file: String): Map<String, String> {
        if (!exists(context, file)) return emptyMap()
        return runCatching {
            val key = androidx.security.crypto.MasterKey.Builder(context)
                .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
                .build()
            val old = androidx.security.crypto.EncryptedSharedPreferences.create(
                context, file, key,
                androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
            old.all.mapNotNull { (k, v) -> v?.let { k to it.toString() } }.toMap()
        }.onFailure { android.util.Log.w("AWSECRET", "legacy $file unreadable: $it") }
            .getOrDefault(emptyMap())
    }

    fun delete(context: Context, file: String) {
        if (!exists(context, file)) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.deleteSharedPreferences(file)
        } else {
            context.getSharedPreferences(file, Context.MODE_PRIVATE).edit().clear().commit()
        }
    }

    private fun exists(context: Context, file: String): Boolean =
        java.io.File(context.applicationInfo.dataDir, "shared_prefs/$file.xml").exists()
}
