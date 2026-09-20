package app.archivewatch.android.studio

// Watch Together Studio's live state, shared between Detail and the player
// (ANDROID-DESIGN §9.1). The Android counterpart of the Apple side's
// `StudioSession`, and it exists for the same reason: Detail decides to go
// live, the PLAYER is where the film and the surfaces are, and the two are
// different destinations in the same nav graph.
//
// It holds ONE show, because a device produces one show at a time. Everything
// about rendering, encoding and publishing stays in `StudioEngine`.

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.util.UnstableApi
import app.archivewatch.android.data.CatalogItem
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@UnstableApi
object StudioController {

    /** The film the host asked to broadcast, set before the player exists. */
    var armedFilmID: String? by mutableStateOf(null)
        private set
    var armedTitle: String by mutableStateOf("")
        private set
    var armedSubtitle: String by mutableStateOf("")
        private set
    var armedProvenance: String? by mutableStateOf(null)
        private set

    /** Why the Studio refused, for the surface that asked. */
    var refusal: String? by mutableStateOf(null)

    var isLive: Boolean by mutableStateOf(false)
    /** Why a signed-in host is NOT reaching their channel, or null. Shown,
     *  never swallowed (§5): a broadcast that quietly fell back to nothing is
     *  precisely the state this path exists to make impossible. */
    var goLiveProblem: String? by mutableStateOf(null)
        private set
    var health: StudioHealth by mutableStateOf(StudioHealth())
        private set

    // What the §9.3 bottom sheet drives.
    var showsCamera: Boolean by mutableStateOf(true)

    /**
     * §4's faders, on the 0-10 scale every platform shows (Rule 8.8c).
     *
     * Compose state rather than a pass-through to the engine, so the panel
     * redraws when they move; the values are pushed into the mix on change.
     * Both default to 8 — unity, the film's and the voice's own level — so a
     * host who never opens the panel is already where they would have set it.
     */
    private var _filmLevel by mutableStateOf(MixLevel.UNITY)
    private var _micLevel by mutableStateOf(MixLevel.UNITY)
    private var _duck by mutableStateOf(true)

    /**
     * Assignable like `showsCamera`, with the push into the mix in the
     * setter. A separate `setFilmLevel(...)` beside a `private set` property
     * is the same JVM signature and will not compile — and a pair of them
     * would be two ways to say one thing, which is how a panel and a mix get
     * out of step.
     */
    var filmLevel: Double
        get() = _filmLevel
        set(v) {
            _filmLevel = v.coerceIn(0.0, MixLevel.MAXIMUM)
            engine?.mix?.filmGain = MixLevel.gain(_filmLevel)
        }

    var micLevel: Double
        get() = _micLevel
        set(v) {
            _micLevel = v.coerceIn(0.0, MixLevel.MAXIMUM)
            engine?.mix?.micGain = MixLevel.gain(_micLevel)
        }

    var duckEnabled: Boolean
        get() = _duck
        set(v) { _duck = v; engine?.mix?.duckEnabled = v }

    /** What the audience is actually hearing, for the meters. */
    val programLevel: Float get() = engine?.mix?.programLevel ?: 0f
    val voiceLevel: Float get() = engine?.voice?.level ?: 0f
    val ducking: Boolean get() = engine?.mix?.ducking ?: false
    /** Whether there is a voice at all — a television has none (§8.8). */
    val hasVoice: Boolean get() = engine?.voice != null
    var panelOpen: Boolean by mutableStateOf(false)

    private var engine: StudioEngine? = null
    private var audioTap: StudioFilmAudioTap? = null
    /** The host in the show. Null on a television, which has neither. */
    private var camera: StudioCamera? = null
    private var mic: StudioMicAudio? = null
    /** Kept so the microphone can be opened once the film's rate is known. */
    private var showContext: android.content.Context? = null

    // The host's camera and microphone report through `health.hostFault` and
    // `health.cameraFramesDelivered`, NOT through accessors here. An accessor
    // that no surface reads is the shape that hid a dead capture session on
    // Apple for a day (§9.kkkkk), and this file had two of them for about
    // twenty minutes.

    /**
     * Detail's entry point. Applies the rights gate and either refuses with a
     * sentence the host can act on, or arms the session.
     * Returns true when the caller should open the player.
     */
    fun arm(item: CatalogItem): Boolean {
        val why = StudioRights.refusal(item.rightsBucket, item.contentType, item.year)
        if (why != null) {
            refusal = why
            return false
        }
        armedFilmID = item.archiveID
        armedTitle = item.title
        armedSubtitle = listOfNotNull(item.year?.toString(), item.director)
            .filter { it.isNotBlank() }.joinToString(" · ")
        armedProvenance = if (item.rightsBucket == "safe_pd_age" && item.year != null)
            "Public domain — published ${item.year}, before 1930" else null
        return true
    }

    fun disarm() { armedFilmID = null }

    /**
     * The tap the player installed, handed over when the player is BUILT.
     *
     * It cannot be handed over when the host goes live: a Media3 audio
     * processor is part of the `AudioSink` chain, which is fixed at
     * `ExoPlayer.Builder` time, so a tap attached later reaches nothing. The
     * previous shape asked for the tap by film id at go-live and was called
     * from nowhere — which is why every Android broadcast went out with NO
     * AUDIO TRACK at all, proved on the Google TV from mediamtx's own
     * `tracks: [H264]` (§9). The film's own AAC track was there the whole
     * time; nothing was carrying it.
     */
    fun attachTap(tap: StudioFilmAudioTap) { audioTap = tap }

    /**
     * The surface reports how far the audio tap runs AHEAD of playback, in
     * microseconds (§9.hhh). Only the player's own screen can see both clocks.
     */
    @Volatile private var audioLeadUs: Long = 0
    fun reportAudioLead(us: Long) { if (us > 0) audioLeadUs = us }

    /** Which tap a show started now would carry. Read by the tests. */
    val attachedTap: StudioFilmAudioTap? get() = audioTap

    /** The player is going away; its tap must not outlive it. */
    fun detachTap(tap: StudioFilmAudioTap) { if (audioTap === tap) audioTap = null }

    /**
     * Called by the player once it exists. A no-op unless this is the film the
     * host armed — a host who goes live on one title and then plays another
     * has not armed the second.
     */
    fun startIfArmed(scope: CoroutineScope, archiveID: String, overlayWidth: Int, overlayHeight: Int,
                     thermalStatus: () -> Int = { 0 },
                     context: android.content.Context? = null) {
        if (armedFilmID != archiveID || isLive) return
        armedFilmID = null
        val e = StudioEngine(thermalStatus = thermalStatus, audioLeadUs = { audioLeadUs })
        e.layoutShowsCamera = showsCamera
        // A NEW ENGINE STARTS WHERE THE HOST LEFT THE FADERS, not at unity.
        // Going live a second time with the panel still reading 3 and the mix
        // silently back at 8 is the kind of lie §4 exists to prevent.
        e.mix.filmGain = MixLevel.gain(_filmLevel)
        e.mix.micGain = MixLevel.gain(_micLevel)
        e.mix.duckEnabled = _duck
        engine = e
        // A REAL destination when the host is signed in; the bench address
        // otherwise. Until now this was the bench address ONLY, so the engine
        // composited, encoded and reported healthy while reaching nobody —
        // §9.ccc's shape, on the last platform still carrying it.
        val benchDest = app.archivewatch.android.ui.DeepLinks.pendingStudioDest.value
        val benchKey = app.archivewatch.android.ui.DeepLinks.pendingStudioKey.value ?: "awbench"

        // RESOLVE FIRST, THEN START — the engine takes its destination at
        // `start()` and the render loop captures it, so there is no way to
        // adopt one later without making the destination mutable under a
        // running loop. Apple does the same: resolve, then start.
        //
        // And resolving asks Twitch three questions over the network, so it
        // cannot happen on this thread. `startIfArmed` runs on Compose's main
        // dispatcher and would throw NetworkOnMainThreadException — Decision
        // 130's Android lesson, where a reconnect supervisor passed a JVM test
        // and threw on every attempt in the app because the test called it from
        // its own thread.
        if (context != null && StudioGoLive.canGoLive(context)) {
            scope.launch(Dispatchers.IO) {
                val resolved = runCatching {
                    StudioGoLive.twitchDestination(context, armedTitle)
                }.onFailure {
                    goLiveProblem = it.message ?: "Twitch refused the broadcast."
                }.getOrNull()
                withContext(Dispatchers.Main) {
                    launchEngine(e, scope, overlayWidth, overlayHeight,
                                 resolved?.server ?: benchDest,
                                 resolved?.key ?: (if (benchDest != null) benchKey else ""))
                }
            }
            isLive = true
            return
        }
        launchEngine(e, scope, overlayWidth, overlayHeight,
                     benchDest, if (benchDest != null) benchKey else "")
        showContext = context
        openHost(e, context)
        isLive = true
    }

    /**
     * THE HOST — the camera now, the microphone when the film's rate is known.
     *
     * Neither is required. §8.8's rule is that an absent camera is NORMAL, and
     * a television has neither, so both failures are recorded as sentences and
     * the show goes on carrying the film. The engine's tile is drawn only once
     * `cameraFramesAvailable > 0`, so a camera that never opens costs nothing
     * on screen either.
     *
     * The MICROPHONE cannot open yet on purpose: it must record at the FILM's
     * sample rate (mixing is sample for sample into the film's own buffers),
     * and the tap does not know that rate until the first buffer arrives,
     * which is after the show has begun. `openMicrophoneIfReady` is called
     * from the health tick until it succeeds.
     */
    private fun openHost(e: StudioEngine, context: android.content.Context?) {
        if (context == null) return
        val texture = e.cameraTexture
        if (texture != null) {
            val c = StudioCamera()
            if (c.open(context, texture)) {
                camera = c
                e.cameraAspect = c.aspect
            } else {
                // Kept anyway: its `problem` is the sentence the host reads.
                camera = c
            }
        }
    }

    /**
     * Opens the microphone once the film has told us its rate. Idempotent, and
     * called once a second from the health tick until it takes.
     */
    private fun openMicrophoneIfReady() {
        if (mic != null) return
        val ctx = showContext ?: return
        val rate = audioTap?.sampleRate ?: 0
        if (rate <= 0) return
        val m = StudioMicAudio()
        // Kept whether or not it opened: a refusal is a sentence, not silence.
        mic = m
        if (m.start(ctx, rate, audioTap?.channelCount ?: 2)) {
            engine?.voice = m
        }
    }

    /** The engine start itself, shared by the resolved and bench paths. */
    private fun launchEngine(e: StudioEngine, scope: CoroutineScope,
                             overlayWidth: Int, overlayHeight: Int,
                             destination: String?, streamKey: String) {
        e.start(
            scope = scope,
            destination = destination,
            streamKey = streamKey,
            audioTap = audioTap,
            overlay = StudioOverlayBitmap.lowerThird(
                overlayWidth, overlayHeight, armedTitle, armedSubtitle, armedProvenance),
            // The SURFACE owns the film's title and provenance, so it supplies
            // the re-render; the engine decides when chat has changed enough
            // to need one.
            overlayForChat = { lines ->
                StudioOverlayBitmap.withChat(
                    overlayWidth, overlayHeight, armedTitle, armedSubtitle, armedProvenance, lines)
            },
            chatChannel = app.archivewatch.android.ui.DeepLinks.pendingStudioChat.value,
        )
    }

    /**
     * The film's own surface while the Studio owns it.
     *
     * `Player.setVideoSurface` is EXCLUSIVE on Android, so a live Studio takes
     * the player's video output: the player renders into the engine's texture
     * and the engine paints the composed program onto the screen instead
     * (§6.2j). Null when not live, and the player then behaves normally.
     */
    val filmSurface: android.view.Surface? get() = engine?.filmSurface

    /** The host's screen, handed to the engine to paint the program onto. */
    fun setDisplaySurface(surface: android.view.Surface?) {
        engine?.setDisplaySurface(surface)
    }

    /**
     * One health sample a second, for the §9.4 readout — and the place a show
     * that ended ITSELF gets cleaned up.
     *
     * §6.5's critical path ends the render loop from inside it, so without
     * this the engine would stop producing while the encoder, the publisher,
     * both surfaces and the GL context stayed alive and `isLive` stayed true.
     * The host would see a frozen program and no way back.
     */
    suspend fun pollHealth() {
        val e = engine ?: return
        // The microphone waits for the film to say what rate it runs at, and
        // that is not known until the first buffer arrives. This is the retry.
        openMicrophoneIfReady()
        // THE HOST'S FAULTS GO INTO HEALTH, where something actually reads
        // them. The camera's complaint outranks the microphone's: a host who
        // cannot be seen notices before one who cannot be heard.
        health = e.health.copy(
            hostFault = camera?.problem ?: mic?.problem,
            cameraFramesDelivered = camera?.framesDelivered?.get() ?: 0,
        )
        if (e.health.endedReason != null && isLive) {
            val why = e.health.endedReason
            end()
            // Surfaced, not swallowed: the host is owed the reason their
            // broadcast stopped.
            refusal = why
        }
    }

    suspend fun end() {
        // THE HOST'S HARDWARE GOES FIRST. A camera or a microphone that
        // outlives its show is a light left on in someone's house — and on
        // Android an AudioRecord that is never released keeps the input
        // device claimed for the whole process.
        camera?.close(); camera = null
        mic?.stop(); mic = null
        showContext = null
        engine?.voice = null
        engine?.stop()
        engine = null
        audioTap = null
        isLive = false
        panelOpen = false
        health = StudioHealth()
    }
}
