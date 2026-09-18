package app.archivewatch.android.studio

// Signing in to a streaming platform, on Android (docs/WATCH-TOGETHER.md §6.1,
// Decision 128). The Kotlin counterpart of Studio/StudioPlatformAuth.swift.
//
// TWITCH FIRST, AND TWITCH ALONE FOR NOW, because it is the only half that
// needs nothing from anybody: its Device Code Grant is a PUBLIC client with no
// secret and no PKCE, and the same client id Apple already uses works here —
// a Twitch client id is not device-specific. YouTube on Android needs a client
// of its own and is deliberately not faked in here (see the note at the end).
//
// The device flow is also the right shape for this platform rather than a
// concession: Android ships on phones AND on televisions (Google TV, Fire TV),
// and a television has no keyboard. Apple gets away with a web sheet because
// tvOS hands the session to a nearby iPhone (§9.yyy); Android has no such
// hand-off, which is exactly the case Decision 128 reserved a device flow for.
//
// What the RULES are, and why they are public: the poll discriminator is a
// pure function so a test can assert the rule the PRODUCT runs rather than
// re-implementing it (Decision 119). Twitch answers HTTP 400 for every
// unconfirmed poll, so the status carries no information and the message is
// the only discriminator — measured on the live endpoint, not assumed.

import android.content.Context
import app.archivewatch.android.BuildConfig
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

object StudioPlatformAuth {

    private val http: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()
    }

    const val TWITCH = "twitch"

    /// The scopes a broadcast actually spends. Named explicitly rather than
    /// derived, because a token issued before a scope was added still
    /// validates — it simply cannot do the thing.
    val twitchScopes = listOf(
        "channel:read:stream_key",
        "channel:manage:broadcast",
        "user:read:chat",
    )
    private val twitchRequiredScopes = listOf(
        "channel:read:stream_key",
        "channel:manage:broadcast",
    )

    fun twitchClientId(): String? = BuildConfig.AW_TWITCH_CLIENT_ID.ifEmpty { null }

    /// A missing credential is a STATE the screen can render, not an error
    /// (Decision 128). Null when the build is configured.
    fun configurationProblem(): String? =
        if (twitchClientId() != null) null
        else "Signing in to Twitch is not set up in this build yet. It needs an " +
            "application registered on the Twitch developer console and its client id " +
            "in gradle.properties as awTwitchClientId."

    // MARK: - The device flow

    data class Pending(
        /// Shown to the host AND encoded in the QR. Twitch's verification_uri
        /// already carries the user code — measured 2026-09-18 — so scanning
        /// reaches a pre-filled activation page.
        val verificationUri: String,
        val userCode: String,
        val deviceCode: String,
        val intervalSeconds: Long,
        val expiresAtMillis: Long,
    )

    fun begin(): Pending {
        val clientId = twitchClientId() ?: error("no Twitch client id")
        val body = FormBody.Builder()
            .add("client_id", clientId)
            .add("scopes", twitchScopes.joinToString(" "))
            .build()
        val req = Request.Builder()
            .url("https://id.twitch.tv/oauth2/device").post(body).build()
        http.newCall(req).execute().use { resp ->
            val o = JSONObject(resp.body?.string().orEmpty())
            val device = o.optString("device_code").ifEmpty { null }
            val user = o.optString("user_code").ifEmpty { null }
            val uri = o.optString("verification_uri").ifEmpty { null }
            if (device == null || user == null || uri == null) {
                throw IllegalStateException("Twitch would not start a device sign-in.")
            }
            return Pending(
                verificationUri = uri,
                userCode = user,
                deviceCode = device,
                intervalSeconds = o.optLong("interval", 5L),
                expiresAtMillis = System.currentTimeMillis() +
                    o.optLong("expires_in", 1800L) * 1000L,
            )
        }
    }

    sealed class PollOutcome {
        object KeepWaiting : PollOutcome()
        object BackOff : PollOutcome()
        data class Refused(val why: String) : PollOutcome()
    }

    /// Twitch answers EVERY poll with HTTP 400 until the host confirms, so the
    /// status is not the answer. Measured against the live endpoint:
    ///
    ///     not yet confirmed    400  {"message":"authorization_pending"}
    ///     a dead device code   400  {"message":"invalid device code"}
    ///
    /// Written as a `when` on the KNOWN messages rather than
    /// `!message.contains("pending")`, so an unrecognised message waits instead
    /// of ending a sign-in that might still succeed.
    fun pollOutcome(message: String): PollOutcome = when {
        message.contains("authorization_pending") -> PollOutcome.KeepWaiting
        message.contains("slow_down") -> PollOutcome.BackOff
        message.isBlank() -> PollOutcome.KeepWaiting
        else -> PollOutcome.Refused(message)
    }

    /// Blocking; callers run it off the main thread. Returns when the host has
    /// confirmed on their phone, or throws when the code dies.
    fun poll(context: Context, pending: Pending): StudioToken {
        val clientId = twitchClientId() ?: error("no Twitch client id")
        var interval = pending.intervalSeconds
        while (System.currentTimeMillis() < pending.expiresAtMillis) {
            Thread.sleep(interval * 1000L)
            val body = FormBody.Builder()
                .add("client_id", clientId)
                .add("device_code", pending.deviceCode)
                .add("grant_type", "urn:ietf:params:oauth:grant-type:device_code")
                .build()
            val req = Request.Builder()
                .url("https://id.twitch.tv/oauth2/token").post(body).build()
            val o = http.newCall(req).execute().use { resp ->
                JSONObject(resp.body?.string().orEmpty())
            }
            val access = o.optString("access_token").ifEmpty { null }
            if (access != null) {
                val token = StudioToken(
                    access = access,
                    refresh = o.optString("refresh_token").ifEmpty { null },
                    expiresAtMillis = System.currentTimeMillis() +
                        o.optLong("expires_in", 14400L) * 1000L,
                )
                // MUST be checked — a one-time-use refresh token that fails to
                // store signs the host out at the next call (§9.rrr).
                if (!StudioTokenStore.save(context, TWITCH, token)) {
                    throw IllegalStateException(
                        "Signed in to Twitch, but the token could not be stored. Sign in again.")
                }
                return token
            }
            when (val outcome = pollOutcome(o.optString("message"))) {
                is PollOutcome.KeepWaiting -> Unit
                is PollOutcome.BackOff -> interval += 5
                is PollOutcome.Refused ->
                    throw IllegalStateException("Twitch refused the sign-in: ${outcome.why}")
            }
        }
        throw IllegalStateException("The Twitch code expired before it was confirmed.")
    }

    /// One-time-use refresh tokens: the NEW one must be stored or the host is
    /// signed out silently at the next call.
    fun refresh(context: Context, token: StudioToken): StudioToken {
        val clientId = twitchClientId() ?: error("no Twitch client id")
        val refresh = token.refresh ?: throw IllegalStateException("Sign in to Twitch again.")
        val body = FormBody.Builder()
            .add("client_id", clientId)
            .add("refresh_token", refresh)
            .add("grant_type", "refresh_token")
            .build()
        val req = Request.Builder()
            .url("https://id.twitch.tv/oauth2/token").post(body).build()
        val o = http.newCall(req).execute().use { JSONObject(it.body?.string().orEmpty()) }
        val access = o.optString("access_token").ifEmpty { null }
            ?: throw IllegalStateException("Sign in to Twitch again.")
        val renewed = StudioToken(
            access = access,
            refresh = o.optString("refresh_token").ifEmpty { null } ?: refresh,
            expiresAtMillis = System.currentTimeMillis() + o.optLong("expires_in", 14400L) * 1000L,
        )
        if (!StudioTokenStore.save(context, TWITCH, renewed)) {
            throw IllegalStateException(
                "Twitch renewed the sign-in but it could not be stored. Sign in again.")
        }
        return renewed
    }

    fun token(context: Context): String {
        configurationProblem()?.let { throw IllegalStateException(it) }
        val stored = StudioTokenStore.load(context, TWITCH)
            ?: throw IllegalStateException(
                "Sign in to Twitch to stream. Archive Watch will fetch the stream key itself.")
        return if (stored.isFresh) stored.access else refresh(context, stored).access
    }

    // MARK: - Readiness, asked with a READ

    data class Account(val login: String, val scopes: List<String>)

    sealed class Readiness {
        object Ready : Readiness()
        data class Blocked(val why: String) : Readiness()
    }

    /// Whose channel, and can this sign-in do it — from ONE read that does not
    /// touch the stream key.
    ///
    /// The obvious check is forbidden: readiness could be answered by fetching
    /// the key, and §5 says a key does not outlive the session that fetched it.
    /// A probe that fetches a credential to check a credential has created the
    /// exposure it was verifying. `/oauth2/validate` returns login and scopes
    /// and touches nothing.
    ///
    /// Measured with its control (2026-09-18):
    ///     bogus token  401 {"message":"invalid access token"}
    ///     NO header    401 {"message":"missing authorization token"}
    /// Same status for both — the message is the discriminator, again.
    fun account(context: Context): Account {
        val access = token(context)
        val req = Request.Builder()
            .url("https://id.twitch.tv/oauth2/validate")
            .header("Authorization", "OAuth $access")
            .build()
        val o = http.newCall(req).execute().use { resp ->
            val json = JSONObject(resp.body?.string().orEmpty())
            if (!resp.isSuccessful) {
                val why = json.optString("message").ifEmpty { "HTTP ${resp.code}" }
                throw IllegalStateException("Twitch will not accept this sign-in: $why")
            }
            json
        }
        val scopes = o.optJSONArray("scopes")?.let { arr ->
            (0 until arr.length()).map { arr.getString(it) }
        } ?: emptyList()
        return Account(o.optString("login"), scopes)
    }

    fun readiness(context: Context): Readiness {
        val absent = twitchRequiredScopes.filter { it !in account(context).scopes }
        return if (absent.isEmpty()) Readiness.Ready
        else Readiness.Blocked(
            "This Twitch sign-in is missing permission to " +
                (if ("channel:read:stream_key" in absent) "start a stream"
                 else "set the stream title") +
                ". Sign out and sign in again to grant it.")
    }

    // YOUTUBE IS DELIBERATELY ABSENT. Android cannot reuse Apple's client (a
    // Google OAuth client is bound to its platform and the iOS one is refused
    // by TYPE — measured, §9.www), and on a television the flow it needs is
    // Google's device grant, which requires a client of type "TVs and Limited
    // Input devices" carrying a SECRET. Writing a half of it that cannot work
    // would be exactly the "declared somewhere no other platform could see it"
    // defect §9.ccc found on Apple. It waits for a registration.
}
