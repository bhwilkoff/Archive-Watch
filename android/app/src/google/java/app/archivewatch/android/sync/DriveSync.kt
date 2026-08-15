package app.archivewatch.android.sync

import android.app.Activity
import android.content.SharedPreferences
import app.archivewatch.android.BuildConfig
import app.archivewatch.android.data.UserStateStore
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

/**
 * Cross-device sync via the user's OWN Google Drive appDataFolder — the
 * no-backend analog of CloudKit (Decision 028), sharing `awsync.json` with
 * the web viewer (js/drivesync.js) so a browser and this phone converge on
 * one watch record. Merge rules are Decision 078's: position is
 * last-writer-wins by `at`; HISTORY is a UNION (earliest firstAt, max
 * plays, everDone-anywhere = everDone-everywhere).
 *
 * DORMANT until the owner supplies the OAuth client
 * (docs/google-oauth-setup.md): `isConfigured` reads the
 * AW_GOOGLE_SERVER_CLIENT_ID BuildConfig field, empty by default, and every
 * UI entry point hides on false. GMS presence is still checked at runtime
 * (a Play build can land on a GMS-less device) by letting the authorization
 * call fail soft — sync is a bonus, it must never take the app down.
 */
object DriveSync {
    const val IS_SUPPORTED: Boolean = true
    private const val FILE = "awsync.json"
    private const val SCOPE_APPDATA = "https://www.googleapis.com/auth/drive.appdata"

    val isConfigured: Boolean get() = BuildConfig.AW_GOOGLE_SERVER_CLIENT_ID.isNotEmpty()

    private var prefs: SharedPreferences? = null
    private var accessToken: String? = null
    private val http = OkHttpClient()

    fun attachPrefs(p: SharedPreferences) { prefs = p }
    val isSignedIn: Boolean get() = prefs?.getBoolean("drive_sync_on", false) == true
    val lastSyncAt: Long get() = prefs?.getLong("drive_sync_at", 0) ?: 0

    /** Ask for appdata authorization (shows Google's consent UI when needed). */
    fun signIn(activity: Activity, userState: UserStateStore, onDone: (Boolean) -> Unit) {
        if (!isConfigured) { onDone(false); return }
        val request = AuthorizationRequest.builder()
            .setRequestedScopes(listOf(Scope(SCOPE_APPDATA)))
            .build()
        Identity.getAuthorizationClient(activity)
            .authorize(request)
            .addOnSuccessListener { result ->
                // A pendingIntent means consent UI is required; launching it
                // needs an ActivityResult seam — wired when the client ID
                // exists and this can actually be exercised. Token-in-hand is
                // the silent-grant path.
                val token = result.accessToken
                if (token != null) {
                    accessToken = token
                    prefs?.edit()?.putBoolean("drive_sync_on", true)?.apply()
                    syncNow(userState) { onDone(it) }
                } else {
                    onDone(false)
                }
            }
            .addOnFailureListener { onDone(false) }
    }

    fun signOut() {
        prefs?.edit()?.putBoolean("drive_sync_on", false)?.apply()
        accessToken = null
    }

    fun syncNow(userState: UserStateStore, onDone: (Boolean) -> Unit) {
        val token = accessToken ?: run { onDone(false); return }
        CoroutineScope(Dispatchers.IO).launch {
            val ok = runCatching {
                val fileId = findFile(token)
                val cloud = fileId?.let { pull(token, it) }
                val merged = merge(cloud, userState)
                push(token, fileId, merged)
                prefs?.edit()?.putLong("drive_sync_at", System.currentTimeMillis())?.apply()
                true
            }.getOrDefault(false)
            withContext(Dispatchers.Main) { onDone(ok) }
        }
    }

    private fun findFile(token: String): String? {
        val req = Request.Builder()
            .url("https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=name%3D%27$FILE%27&fields=files(id)")
            .header("Authorization", "Bearer $token").build()
        http.newCall(req).execute().use { r ->
            if (!r.isSuccessful) return null
            val files = JSONObject(r.body!!.string()).optJSONArray("files") ?: return null
            return if (files.length() > 0) files.getJSONObject(0).getString("id") else null
        }
    }

    private fun pull(token: String, fileId: String): JSONObject? {
        val req = Request.Builder()
            .url("https://www.googleapis.com/drive/v3/files/$fileId?alt=media")
            .header("Authorization", "Bearer $token").build()
        http.newCall(req).execute().use { r ->
            return if (r.isSuccessful) runCatching { JSONObject(r.body!!.string()) }.getOrNull()
            else null
        }
    }

    private fun push(token: String, fileId: String?, blob: JSONObject) {
        val body = blob.toString().toRequestBody("application/json".toMediaType())
        val req = if (fileId != null) {
            Request.Builder()
                .url("https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=media")
                .header("Authorization", "Bearer $token")
                .patch(body).build()
        } else {
            val boundary = "awsyncb"
            val multipart = ("--$boundary\r\nContent-Type: application/json\r\n\r\n" +
                "{\"name\":\"$FILE\",\"parents\":[\"appDataFolder\"]}" +
                "\r\n--$boundary\r\nContent-Type: application/json\r\n\r\n" +
                blob.toString() + "\r\n--$boundary--")
                .toRequestBody("multipart/related; boundary=$boundary".toMediaType())
            Request.Builder()
                .url("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")
                .header("Authorization", "Bearer $token")
                .post(multipart).build()
        }
        http.newCall(req).execute().close()
    }

    /** Decision 078 merge; writes cloud-newer records into the store and
     * returns the union blob to push back. Shares the web's field names. */
    private suspend fun merge(cloud: JSONObject?, store: UserStateStore): JSONObject {
        val localProgress = store.history(limit = 10_000)
        val byId = localProgress.associateBy { it.archiveID }.toMutableMap()
        val cloudProgress = cloud?.optJSONArray("progress") ?: JSONArray()
        for (i in 0 until cloudProgress.length()) {
            val p = cloudProgress.getJSONObject(i)
            val id = p.optString("id"); if (id.isEmpty()) continue
            val mine = byId[id]
            val cAt = p.optLong("at")
            val cPosMs = (p.optDouble("position", 0.0) * 1000).toLong()
            val cDurMs = (p.optDouble("duration", 0.0) * 1000).toLong()
            val first = minOf(mine?.firstWatchedAt?.takeIf { it > 0 } ?: Long.MAX_VALUE,
                              p.optLong("firstAt").takeIf { it > 0 } ?: Long.MAX_VALUE)
                .takeIf { it != Long.MAX_VALUE } ?: cAt
            val plays = maxOf(mine?.playCount ?: 1, p.optInt("plays", 1))
            val done = (mine?.everCompleted == true) || p.optBoolean("everDone", false)
            val useCloudPos = mine == null || cAt > mine.updatedAt
            store.putProgressRaw(
                id,
                if (useCloudPos) cPosMs else mine!!.positionMs,
                if (useCloudPos) cDurMs else mine!!.durationMs,
                maxOf(cAt, mine?.updatedAt ?: 0), first, plays, done,
            )
        }
        // Rebuild the union blob from the store (now merged).
        val out = JSONArray()
        for (w in store.history(limit = 10_000)) {
            out.put(JSONObject()
                .put("id", w.archiveID)
                .put("position", w.positionMs / 1000.0)
                .put("duration", w.durationMs / 1000.0)
                .put("at", w.updatedAt)
                .put("firstAt", w.firstWatchedAt)
                .put("plays", w.playCount)
                .put("everDone", w.everCompleted))
        }
        return JSONObject().put("v", 1).put("at", System.currentTimeMillis())
            .put("progress", out)
    }
}
