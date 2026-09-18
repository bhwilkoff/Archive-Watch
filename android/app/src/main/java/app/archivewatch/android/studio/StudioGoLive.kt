package app.archivewatch.android.studio

// Turning a signed-in host into an address (docs/WATCH-TOGETHER.md §4).
//
// The Kotlin counterpart of Swift's `StudioGoLive`. Before this, Android's
// `StudioController` passed `destination = benchDest` and nothing else: with no
// bench address the engine composited, encoded and reported healthy while
// reaching nobody — the same shape §9.ccc found on tvOS and macOS, where the
// credential path existed in exactly one file no other platform could see.
//
// TWITCH ONLY, for the reason given in `StudioPlatformAuth`: its device grant
// is a public client that needs no secret and no registration Android does not
// already have. YouTube needs a Google client of its own and is absent rather
// than half-written.

import android.content.Context

object StudioGoLive {

    /** An address and the key that opens it. Never logged, never stored. */
    data class Destination(val server: String, val key: String, val backupServer: String?)

    /**
     * BLOCKING — call from `Dispatchers.IO`, never the main thread.
     *
     * Decision 130's Android lesson is exactly this shape: the reconnect
     * supervisor passed a JVM test and threw `NetworkOnMainThreadException` on
     * every attempt in the app, because the test called it from its own thread
     * and the app used Compose's main dispatcher. A harness can prove the logic
     * and say nothing about where the logic RUNS.
     */
    fun twitchDestination(context: Context, title: String, category: String? = null): Destination {
        val token = StudioPlatformAuth.token(context)
        val clientId = StudioPlatformAuth.twitchClientId()
            ?: throw IllegalStateException("No Twitch client id in this build.")
        val creds = TwitchLive(token, clientId).prepare(title, category)
        return Destination(creds.server, creds.key, creds.backupServer)
    }

    /** Whether a real destination could be resolved at all, without asking for one. */
    fun canGoLive(context: Context): Boolean =
        StudioPlatformAuth.configurationProblem() == null &&
            StudioTokenStore.isSignedIn(context, StudioPlatformAuth.TWITCH)
}
