package app.archivewatch.android.sync

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.SharedPreferences
import android.util.Log
import app.archivewatch.android.BuildConfig
import app.archivewatch.android.data.UserChannelRec
import app.archivewatch.android.data.UserPlaylist
import app.archivewatch.android.data.UserStateStore
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import kotlin.coroutines.resume

/**
 * Cross-device sync via the user's OWN Google Drive appDataFolder — the
 * no-backend analog of CloudKit (Decision 028). One file, `awsync.json`,
 * shared with the web viewer (js/drivesync.js) so a phone, a Google TV and
 * a browser signed into the same Google account converge on one library.
 *
 * Blob (v2, shared field names with the web):
 *   favorites  [{id, addedAt}]                       union minus tombstones
 *   playlists  [{id, name, archiveIDs, createdAt, modifiedAt}]  LWW by modifiedAt
 *   channels   [{id, name, genre, contentType, decade, createdAt}]  union minus tombstones
 *   progress   [{id, position(s), duration(s), at, firstAt, plays, everDone}]
 *              position LWW by `at`; HISTORY is a UNION (Decision 078)
 *   tombstones [{kind: fav|pl|ch, id, at}]            union; a re-add newer
 *              than its tombstone clears it
 *
 * Sign-in is optional and gates ONLY sync (per-ecosystem-sync-islands rule
 * 2); status is user-visible (rule 3) through [status]. Token: Google's
 * AuthorizationClient hands back an access token silently once the account
 * has consented, and a PendingIntent for the consent UI the first time —
 * Settings launches it through an ActivityResult seam and hands the result
 * to [onConsentResult]. Works on Android TV the same way (Play services is
 * present on Google TV; the consent UI is TV-styled there).
 *
 * The amazon flavor has a stub twin with identical signatures: Fire OS has
 * no Play services, so this file never compiles there (Decision 047).
 */
object DriveSync {
    const val IS_SUPPORTED: Boolean = true
    private const val TAG = "AWSYNC"
    private const val FILE = "awsync.json"
    private const val SCOPE_APPDATA = "https://www.googleapis.com/auth/drive.appdata"
    private const val TOMBSTONE_TTL_MS = 90L * 24 * 3600_000

    val isConfigured: Boolean get() = BuildConfig.AW_GOOGLE_SERVER_CLIENT_ID.isNotEmpty()

    data class Status(
        val signedIn: Boolean = false,
        val account: String? = null,
        val lastSyncAt: Long = 0,
        val lastError: String? = null,
        val syncing: Boolean = false,
    )

    private val _status = MutableStateFlow(Status())
    val status: StateFlow<Status> = _status
    val isSignedIn: Boolean get() = _status.value.signedIn
    val lastSyncAt: Long get() = _status.value.lastSyncAt

    private var app: Application? = null
    private var prefs: SharedPreferences? = null
    private var store: UserStateStore? = null
    private var scope: CoroutineScope? = null
    private var accessToken: String? = null
    private val http = OkHttpClient()
    private val syncMutex = Mutex()
    private var debounce: Job? = null

    /** Wire once from the Application. Restores the signed-in flag and arms
     *  the triggers: foreground, 60s while active, debounced after edits. */
    fun attach(application: Application, userState: UserStateStore, appScope: CoroutineScope) {
        if (!isConfigured) return
        app = application
        store = userState
        scope = appScope
        val p = application.getSharedPreferences("aw_drive_sync", Context.MODE_PRIVATE)
        prefs = p
        _status.value = Status(
            signedIn = p.getBoolean("on", false),
            account = p.getString("account", null),
            lastSyncAt = p.getLong("at", 0),
        )
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) { syncNow() }
        })
        appScope.launch {
            while (true) {
                delay(60_000)
                if (ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(
                        androidx.lifecycle.Lifecycle.State.STARTED)) syncNow()
            }
        }
        appScope.launch {
            userState.changes.collect { n ->
                // Our own merge writes bump `changes` too; those must not
                // schedule another round trip.
                if (n == userState.lastRemoteApplyChange) return@collect
                if (!isSignedIn) return@collect
                debounce?.cancel()
                debounce = launch { delay(4_000); syncNow() }
            }
        }
    }

    /**
     * Ask Google for appdata authorization. Silent when the account already
     * consented (token in hand → sync); otherwise hands the consent
     * PendingIntent to [launchConsent], and Settings routes the result to
     * [onConsentResult].
     */
    fun signIn(activity: Activity, launchConsent: (IntentSender) -> Unit) {
        if (!isConfigured) return
        _status.value = _status.value.copy(lastError = null)
        Identity.getAuthorizationClient(activity)
            .authorize(request())
            .addOnSuccessListener { result ->
                if (result.hasResolution()) {
                    result.pendingIntent?.intentSender?.let(launchConsent)
                } else {
                    grant(result)
                }
            }
            .addOnFailureListener { e ->
                Log.w(TAG, "authorize failed", e)
                _status.value = _status.value.copy(
                    lastError = "Google sign-in unavailable: " + (e.message ?: e.javaClass.simpleName),
                )
            }
    }

    /** The consent Activity result — completes [signIn]. */
    fun onConsentResult(activity: Activity, data: Intent?) {
        runCatching { Identity.getAuthorizationClient(activity).getAuthorizationResultFromIntent(data) }
            .onSuccess { grant(it) }
            .onFailure { e ->
                _status.value = _status.value.copy(lastError = "Sign-in was not completed.")
                Log.w(TAG, "consent result", e)
            }
    }

    private fun grant(result: AuthorizationResult) {
        val token = result.accessToken
        if (token == null) {
            _status.value = _status.value.copy(lastError = "Google returned no access token.")
            return
        }
        accessToken = token
        prefs?.edit()?.putBoolean("on", true)?.apply()
        _status.value = _status.value.copy(signedIn = true, lastError = null)
        syncNow()
    }

    fun signOut() {
        prefs?.edit()?.clear()?.apply()
        accessToken = null
        _status.value = Status()
    }

    /** Legacy signature kept for call sites; the ActivityResult seam is the real path. */
    fun signIn(activity: Activity, userState: UserStateStore, onDone: (Boolean) -> Unit) {
        signIn(activity) { onDone(false) }
    }

    fun syncNow(userState: UserStateStore, onDone: (Boolean) -> Unit) {
        scope?.launch { onDone(syncOnce()) } ?: onDone(false)
    }

    fun syncNow() {
        if (!isSignedIn) return
        scope?.launch { syncOnce() }
    }

    private fun request(): AuthorizationRequest =
        AuthorizationRequest.builder()
            .setRequestedScopes(listOf(Scope(SCOPE_APPDATA)))
            .build()

    /** A fresh token without UI: once consented, authorize() answers with a
     *  token and no resolution. If consent lapsed, say so in the status
     *  rather than throwing a consent screen at a viewer mid-browse. */
    private suspend fun freshToken(): String? {
        val ctx = app ?: return null
        return suspendCancellableCoroutine { cont ->
            Identity.getAuthorizationClient(ctx).authorize(request())
                .addOnSuccessListener { r ->
                    if (r.hasResolution()) cont.resume(null) else cont.resume(r.accessToken)
                }
                .addOnFailureListener { cont.resume(null) }
        }
    }

    private suspend fun syncOnce(): Boolean = withContext(Dispatchers.IO) {
        val userState = store ?: return@withContext false
        if (!isSignedIn) return@withContext false
        syncMutex.withLock {
            _status.value = _status.value.copy(syncing = true)
            val ok = runCatching {
                val token = freshToken() ?: accessToken
                    ?: throw IllegalStateException("Sign in again to continue syncing.")
                accessToken = token
                if (_status.value.account == null) whoAmI(token)?.let { email ->
                    prefs?.edit()?.putString("account", email)?.apply()
                    _status.value = _status.value.copy(account = email)
                }
                val fileId = findFile(token)
                val cloud = fileId?.let { pull(token, it) }
                val merged = merge(cloud, userState)
                push(token, fileId, merged)
                val now = System.currentTimeMillis()
                prefs?.edit()?.putLong("at", now)?.apply()
                _status.value = _status.value.copy(lastSyncAt = now, lastError = null)
                true
            }.getOrElse { e ->
                Log.w(TAG, "sync failed", e)
                _status.value = _status.value.copy(lastError = e.message ?: e.javaClass.simpleName)
                false
            }
            _status.value = _status.value.copy(syncing = false)
            ok
        }
    }

    // --- Drive REST ---

    private fun whoAmI(token: String): String? {
        val req = Request.Builder()
            .url("https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)")
            .header("Authorization", "Bearer $token").build()
        http.newCall(req).execute().use { r ->
            if (!r.isSuccessful) return null
            return JSONObject(r.body!!.string()).optJSONObject("user")?.optString("emailAddress")
                ?.takeIf { it.isNotEmpty() }
        }
    }

    private fun findFile(token: String): String? {
        val req = Request.Builder()
            .url("https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=name%3D%27$FILE%27&fields=files(id)")
            .header("Authorization", "Bearer $token").build()
        http.newCall(req).execute().use { r ->
            if (r.code == 401 || r.code == 403) throw IllegalStateException("Google Drive access was revoked — sign in again.")
            if (!r.isSuccessful) throw IllegalStateException("Drive list failed (${r.code})")
            val files = JSONObject(r.body!!.string()).optJSONArray("files") ?: return null
            return if (files.length() > 0) files.getJSONObject(0).getString("id") else null
        }
    }

    private fun pull(token: String, fileId: String): JSONObject? {
        val req = Request.Builder()
            .url("https://www.googleapis.com/drive/v3/files/$fileId?alt=media")
            .header("Authorization", "Bearer $token").build()
        http.newCall(req).execute().use { r ->
            if (!r.isSuccessful) throw IllegalStateException("Drive read failed (${r.code})")
            return runCatching { JSONObject(r.body!!.string()) }.getOrNull()
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
        http.newCall(req).execute().use { r ->
            if (!r.isSuccessful) throw IllegalStateException("Drive write failed (${r.code})")
        }
    }

    // --- merge ---

    private fun JSONObject?.arr(key: String): List<JSONObject> {
        val a = this?.optJSONArray(key) ?: return emptyList()
        return (0 until a.length()).mapNotNull { a.optJSONObject(it) }
    }

    /** Applies cloud-newer state into the store and returns the union blob. */
    private suspend fun merge(cloud: JSONObject?, store: UserStateStore): JSONObject {
        val now = System.currentTimeMillis()

        // Tombstones first: union, and they gate everything below.
        val tombs = HashMap<String, Long>()   // "kind:id" -> at
        for (t in store.tombstones()) tombs["${t.kind}:${t.id}"] = t.at
        for (t in cloud.arr("tombstones")) {
            val key = "${t.optString("kind")}:${t.optString("id")}"
            val at = t.optLong("at")
            if (at > (tombs[key] ?: 0)) tombs[key] = at
        }
        tombs.entries.removeAll { now - it.value > TOMBSTONE_TTL_MS }
        fun dead(kind: String, id: String, itemAt: Long): Boolean =
            (tombs["$kind:$id"] ?: 0L) > itemAt

        // Favorites: union minus tombstones.
        val favs = LinkedHashMap<String, Long>()
        for ((id, at) in store.favoritesWithTime()) favs[id] = at
        for (f in cloud.arr("favorites")) {
            val id = f.optString("id"); if (id.isEmpty()) continue
            val at = f.optLong("addedAt")
            if (at > (favs[id] ?: -1L)) favs[id] = at
        }
        for (id in favs.keys.toList()) if (dead("fav", id, favs[id]!!)) favs.remove(id)
        val localFavIDs = store.favoritesWithTime().map { it.first }.toSet()
        for ((id, at) in favs) if (id !in localFavIDs) store.putFavoriteRaw(id, at)
        for (id in localFavIDs) if (id !in favs) store.removeFavoriteRaw(id)

        // Playlists: last writer wins by modifiedAt, minus tombstones.
        val pls = LinkedHashMap<String, UserPlaylist>()
        for (p in store.playlists()) pls[p.id] = p
        for (p in cloud.arr("playlists")) {
            val id = p.optString("id"); if (id.isEmpty()) continue
            val mod = p.optLong("modifiedAt")
            val mine = pls[id]
            if (mine == null || mod > mine.modifiedAt) {
                val ids = p.optJSONArray("archiveIDs")?.let { a -> (0 until a.length()).map { a.optString(it) } }
                    ?: emptyList()
                pls[id] = UserPlaylist(id, p.optString("name"), ids.filter { it.isNotEmpty() },
                    p.optLong("createdAt").takeIf { it > 0 } ?: mod, mod)
            }
        }
        for (id in pls.keys.toList()) if (dead("pl", id, pls[id]!!.modifiedAt)) pls.remove(id)
        val localPl = store.playlists().associateBy { it.id }
        for ((id, p) in pls) if (localPl[id] != p) store.putPlaylistRaw(p)
        for (id in localPl.keys) if (id !in pls) store.removePlaylistRaw(id)

        // Channels: union minus tombstones. The web calls contentType "type".
        val chans = LinkedHashMap<String, UserChannelRec>()
        for (c in store.userChannels()) chans[c.id] = c
        for (c in cloud.arr("channels")) {
            val id = c.optString("id"); if (id.isEmpty() || chans.containsKey(id)) continue
            chans[id] = UserChannelRec(
                id, c.optString("name"),
                c.optString("genre").takeIf { it.isNotEmpty() },
                (c.optString("contentType").takeIf { it.isNotEmpty() }
                    ?: c.optString("type").takeIf { it.isNotEmpty() }),
                if (c.has("decade") && !c.isNull("decade")) c.optInt("decade") else null,
                c.optLong("createdAt").takeIf { it > 0 } ?: now,
            )
        }
        for (id in chans.keys.toList()) if (dead("ch", id, chans[id]!!.createdAt)) chans.remove(id)
        val localCh = store.userChannels().associateBy { it.id }
        for ((id, c) in chans) if (localCh[id] == null) store.putChannelRaw(c)
        for (id in localCh.keys) if (id !in chans) store.removeChannelRaw(id)

        // Progress: position LWW by `at`, history UNION (Decision 078).
        val byId = store.history(limit = 10_000).associateBy { it.archiveID }
        for (p in cloud.arr("progress")) {
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
            if (mine != null && !useCloudPos && first == mine.firstWatchedAt &&
                plays == mine.playCount && done == mine.everCompleted) continue
            store.putProgressRaw(
                id,
                if (useCloudPos) cPosMs else mine!!.positionMs,
                if (useCloudPos) cDurMs else mine!!.durationMs,
                maxOf(cAt, mine?.updatedAt ?: 0), first, plays, done,
            )
        }
        for ((key, at) in tombs) {
            val (kind, id) = key.split(":", limit = 2)
            store.putTombstoneRaw(UserStateStore.Tombstone(kind, id, at))
        }
        store.endRemoteApply()

        // Rebuild the union blob from the store (now merged).
        val out = JSONObject().put("v", 2).put("at", now)
        out.put("favorites", JSONArray().also { a ->
            for ((id, at) in store.favoritesWithTime()) a.put(JSONObject().put("id", id).put("addedAt", at))
        })
        out.put("playlists", JSONArray().also { a ->
            for (p in store.playlists()) a.put(JSONObject()
                .put("id", p.id).put("name", p.name)
                .put("archiveIDs", JSONArray(p.archiveIDs))
                .put("createdAt", p.createdAt).put("modifiedAt", p.modifiedAt))
        })
        out.put("channels", JSONArray().also { a ->
            for (c in store.userChannels()) a.put(JSONObject()
                .put("id", c.id).put("name", c.name)
                .put("genre", c.genre ?: JSONObject.NULL)
                .put("contentType", c.contentType ?: JSONObject.NULL)
                .put("type", c.contentType ?: JSONObject.NULL)
                .put("decade", c.decade ?: JSONObject.NULL)
                .put("createdAt", c.createdAt))
        })
        out.put("progress", JSONArray().also { a ->
            for (w in store.history(limit = 10_000)) a.put(JSONObject()
                .put("id", w.archiveID)
                .put("position", w.positionMs / 1000.0)
                .put("duration", w.durationMs / 1000.0)
                .put("at", w.updatedAt)
                .put("firstAt", w.firstWatchedAt)
                .put("plays", w.playCount)
                .put("everDone", w.everCompleted))
        })
        out.put("tombstones", JSONArray().also { a ->
            for ((key, at) in tombs) {
                val (kind, id) = key.split(":", limit = 2)
                a.put(JSONObject().put("kind", kind).put("id", id).put("at", at))
            }
        })
        return out
    }
}
