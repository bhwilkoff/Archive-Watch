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
    /**
     * The chosen placement, the same five every other platform offers. It
     * replaces a `showsCamera` boolean that could express only two of them;
     * `showsCamera` survives as a derived value so existing callers and the
     * "film only" toggle keep working.
     */
    private var _layout by mutableStateOf(StudioLayout.CORNER)
    var layout: StudioLayout
        get() = _layout
        set(value) {
            _layout = value
            // AND PUSH IT INTO A RUNNING SHOW. The engine took its layout ONCE,
            // at `startIfArmed`, so changing the placement while live moved the
            // radio button and nothing else — on the one platform where the
            // picker exists ONLY while live, which made it inert in its only
            // context. Same shape as the macOS sheet dropping `request.layout`
            // and tvOS hardcoding `.corner`: a control whose value never
            // reaches the engine is worse than no control, because it looks
            // like it worked.
            engine?.layout = value
        }
    /**
     * The card on air, or null for the programme. Pushes into the running
     * engine in its SETTER — the mistake the layout made, and the one the
     * faders had already avoided.
     */
    private var _card by mutableStateOf<StudioCard?>(null)
    var card: StudioCard?
        get() = _card
        set(value) {
            _card = value
            val e = engine ?: return
            e.pendingOverlay = if (value == null) {
                StudioOverlayBitmap.lowerThird(overlayW, overlayH, armedTitle, armedSubtitle,
                                               if (provenanceCleared) null else armedProvenance)
            } else {
                StudioOverlayBitmap.card(overlayW, overlayH, value, armedTitle)
            }
        }

    var showsCamera: Boolean
        get() = layout.showsCamera
        set(value) { layout = if (value) StudioLayout.CORNER else StudioLayout.FILM }

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
    /// Kept so a replacement lower third is rendered at the same size as the
    /// original — a mismatched bitmap would letterbox the caption.
    private var overlayW = 1280
    private var overlayH = 720

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
        e.layout = layout
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
                    // THE HOST GOES ON BOTH PATHS. This branch used to return
                    // without it, so every broadcast that reached a real Twitch
                    // destination carried the film and NOTHING of the person
                    // watching it — no camera, no voice. The owner's rule is
                    // that such a broadcast is not Watch Together at all
                    // (Decision 132), so the defect emptied the feature on the
                    // one path a real audience would ever see. The bench path
                    // below had it, which is why the harness never noticed.
                    beginHost(e, context, overlayWidth, overlayHeight)
                }
            }
            isLive = true
            return
        }
        launchEngine(e, scope, overlayWidth, overlayHeight,
                     benchDest, if (benchDest != null) benchKey else "")
        beginHost(e, context, overlayWidth, overlayHeight)
        isLive = true
    }

    /**
     * The host's camera and microphone, and the state the microphone's retry
     * needs. Called immediately after `launchEngine` on EVERY path — the
     * camera texture does not exist until the engine's GL context does, so the
     * order matters and is the reason this is a function rather than three
     * lines copied twice.
     */
    private fun beginHost(e: StudioEngine, context: android.content.Context?,
                          overlayWidth: Int, overlayHeight: Int) {
        showContext = context
        overlayW = overlayWidth; overlayH = overlayHeight
        openHost(e, context)
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
        // NO TEXTURE YET IS THE NORMAL CASE, not a failure. The camera texture
        // is created by the RENDER thread when it builds the GL context, and
        // this runs on Main the instant after `launchEngine` returns — so the
        // first attempt almost always finds null, returns in silence, and the
        // show carries the film and no host. That is what a Pixel 8a recorded
        // on 2026-09-20: the microphone opened (it has its own retry) and the
        // camera never did, with not one line in the log to say so. The retry
        // lives in `openCameraIfReady`, called from the health tick exactly as
        // the microphone's is.
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
     * Opens the camera once the engine's GL context has made a texture for it.
     * Idempotent, and called once a second from the health tick until it takes
     * — the same shape as the microphone's retry, and for the same reason: the
     * resource is not ready at `start()` and waiting for it with a sleep would
     * be a guess.
     */
    private fun openCameraIfReady() {
        if (camera != null) return
        val e = engine ?: return
        val ctx = showContext ?: return
        val texture = e.cameraTexture ?: return
        val c = StudioCamera()
        if (c.open(ctx, texture)) {
            e.cameraAspect = c.aspect
            android.util.Log.i("AWSTUDIOHOST", "camera opened aspect=" + c.aspect)
        } else {
            android.util.Log.w("AWSTUDIOHOST", "camera refused: " + (c.problem ?: "no reason given"))
        }
        // Kept either way: its `problem` is the sentence the host reads.
        camera = c
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
    /// §4: the provenance line lasts 20 SECONDS of being live, and the clock
    /// starts at LIVE rather than at start — §9.tt measured ~12 s between
    /// starting and the first published packet, so a timer from start spends
    /// most of its window before anyone can see it. A badge that never leaves
    /// is branding, not provenance.
    private var liveSinceMs = 0L
    private var provenanceCleared = false
    private val cameraStall = CameraStallRecovery()
    private var lastCameraFramesSeen = 0

    /**
     * The film's real shape, from the player. Anything outside a sane range is
     * ignored: ExoPlayer reports 0x0 before the first frame, and a 0 aspect
     * would collapse the quad to nothing.
     */
    fun reportFilmAspect(aspect: Float) {
        if (aspect > 0.2f && aspect < 5f) engine?.filmAspect = aspect
    }

    suspend fun pollHealth() {
        val e = engine ?: return
        if (!provenanceCleared && armedProvenance != null) {
            if (e.health.showState == "LIVE") {
                if (liveSinceMs == 0L) liveSinceMs = System.currentTimeMillis()
                else if (System.currentTimeMillis() - liveSinceMs >= 20_000) {
                    provenanceCleared = true
                    e.pendingOverlay = StudioOverlayBitmap.lowerThird(
                        overlayW, overlayH, armedTitle, armedSubtitle, null)
                }
            }
        }
        // The microphone waits for the film to say what rate it runs at, and
        // that is not known until the first buffer arrives. This is the retry.
        openCameraIfReady()
        openMicrophoneIfReady()
        // THE HOST'S FAULTS GO INTO HEALTH, where something actually reads
        // them. The camera's complaint outranks the microphone's: a host who
        // cannot be seen notices before one who cannot be heard.
        val delivered = camera?.framesDelivered?.get() ?: 0
        health = e.health.copy(
            hostFault = camera?.problem ?: mic?.problem,
            cameraFramesDelivered = delivered,
        )
        // RECOVER A CAMERA THAT STOPPED. Android had no guard at all — fairly,
        // until this morning, because until then it had no camera to stall.
        // A phone's camera stops whenever a call arrives, so this platform
        // needs it more than a television does.
        //
        // The rule is called from THIS loop, which is the one Android actually
        // runs. Putting it somewhere that merely looks shared is how the same
        // behaviour reached macOS alone this afternoon.
        val cameraPerSecond = delivered - lastCameraFramesSeen
        lastCameraFramesSeen = delivered
        if (cameraStall.tick(attached = camera != null, framesReceived = delivered.toLong(),
                             framesPerSecond = cameraPerSecond,
                             onAir = e.health.showState == "LIVE")) {
            android.util.Log.i("AWSTUDIOHOST",
                "camera stopped at " + delivered + " frames — recovery attempt " +
                cameraStall.attempts + " of " + CameraStallRecovery.MAX_ATTEMPTS)
            camera?.close()
            camera = null
            openCameraIfReady()
            android.util.Log.i("AWSTUDIOHOST",
                "recovery " + cameraStall.attempts + ": " +
                (if (camera?.problem == null && camera != null) "re-attached" else "no camera"))
        }
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
