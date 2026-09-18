package app.archivewatch.android.studio

// The Android Studio engine — the counterpart of the Apple side's
// `StudioEngine` (docs/WATCH-TOGETHER.md §3.5, ANDROID-DESIGN §9.1).
//
// It owns the render loop and nothing else owns a clock: the loop pulls the
// newest film and camera frames, composites them with the overlay, hands the
// result to MediaCodec and drains both encoders into the publisher. Every
// piece under it was proved separately on real hardware first (§6.2b–e); this
// is the assembly.
//
// ONE RENDER THREAD, and it is a DEDICATED one — not `Dispatchers.Default`.
// An EGL context belongs to the thread that made it current, and a pool
// dispatcher may resume a coroutine on a different thread after every
// `delay()`. The first assembled run died on `eglMakeCurrent failed` for
// exactly that reason: each piece worked alone, and together they hopped
// threads. `updateTexImage`, the draw and the swap must all live on one
// thread, and it must not be the main one — a broadcast that stutters because
// someone scrolled a list is not a broadcast.
//
// THE FILM IS NEVER GATED ON THE BROADCAST. The engine reads what the player
// is already showing; if the encoder falls behind, frames are skipped, not
// queued. The person in the room is watching a film (§3), and a stream is
// something happening beside them.

import android.view.Surface
import app.archivewatch.android.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.launch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** What §6.5 decides to do about a thermal reading. */
enum class ThermalAction { NONE, STEP_DOWN, RESTORE, END_SHOW }

data class StudioHealth(
    val isRunning: Boolean = false,
    val programFramesRendered: Long = 0,
    val programFramesEncoded: Long = 0,
    /** New film frames in the last second; 0 while live is a frozen picture. */
    val filmFramesPerSecond: Int = 0,
    /** Encoded frames in the last second; 0 while the film arrives is the
     *  stall that every other counter calls healthy (§9). */
    val encodedFramesPerSecond: Int = 0,
    val averageRenderMillis: Double = 0.0,
    val hasDestination: Boolean = false,
    /** Android's `PowerManager` thermal status, 0 = NONE (§6.5). */
    val thermalStatus: Int = 0,
    /** What the encoder is ACTUALLY using, which §6.5 can move. */
    val videoBitrateNow: Int = 0,
    /** §5: an adaptive step is shown as it happens, never applied silently. */
    val qualityNote: String? = null,
    /** Set when the show ended on its own account rather than by the host. */
    val endedReason: String? = null,
    /** Why §6.6's last attempt failed, if it did. Never swallowed. */
    val reconnectFault: String? = null,
    val publisher: RtmpHealth = RtmpHealth(),
) {
    /** What the SHOW is doing, in the host's terms — not the transport's. */
    val showState: String get() = when {
        !isRunning -> "OFF"
        filmFramesPerSecond > 0 && encodedFramesPerSecond == 0 -> "STOPPED"
        // §6.6 outranks OFFLINE: while a rebuild is in flight the link is down
        // but the show is not over, and those are different sentences.
        publisher.isReconnecting -> "RECONNECTING"
        publisher.lastError != null -> "OFFLINE"
        !hasDestination -> "NOT SENDING"
        publisher.state == "publishing" -> "LIVE"
        else -> "CONNECTING"
    }

    /// §5: an adaptive-bitrate step is SHOWN as it happens. `qualityNote`
    /// carries the step with its numbers, and it was written by the engine and
    /// rendered by nothing — on either platform — until 2026-09-17. It comes
    /// first because "sent at 2400 instead of 4000 kbps" tells a host what
    /// changed and a state label does not.
    val problem: String? get() = qualityNote ?: when (showState) {
        "STOPPED" -> "The picture has stopped being encoded — your audience is not receiving the show."
        "NOT SENDING" -> "The show is being made but not sent anywhere — no destination is set."
        "RECONNECTING" ->
            "The connection dropped — getting it back. Your audience sees a pause, not an ending."
        "OFFLINE" -> publisher.lastError
        else -> if (isRunning && filmFramesPerSecond == 0)
            "The film has stopped — your audience sees a still picture." else null
    }
}

class StudioEngine(
    private val width: Int = 1280,
    private val height: Int = 720,
    private val frameRate: Int = 30,
    private val videoBitrate: Int = 4_000_000,
    /**
     * §6.5's input, injected rather than read here, for two reasons: the
     * engine holds no `Context` (and `PowerManager` needs one), and a device
     * cannot be made hot on cue — so the seam a harness needs is the same one
     * the platform needs. Values are `PowerManager.THERMAL_STATUS_*`;
     * 0 (NONE) when nobody supplies anything.
     */
    private val thermalStatus: () -> Int = { 0 },
    /**
     * How far the film's audio TAP runs ahead of what the player is actually
     * playing, in microseconds, as measured on this device.
     *
     * `TeeAudioProcessor` sits on the way INTO the audio sink, so it sees PCM
     * before it is audible — measured at **0.565 s** on the Google TV (§9.hhh),
     * which is most of the 0.712 s by which a broadcast's audio led its video
     * (§9.ggg). The surface measures it (it is the only place that can see both
     * the tap and `player.currentPosition`) and the engine applies it, so the
     * correction is THIS pipeline's number rather than a constant that would be
     * wrong on the next device.
     */
    private val audioLeadUs: () -> Long = { 0 },
) {
    @Volatile var health = StudioHealth(); private set

    /** The surface the film's player renders into. Valid once [start] returns. */
    /**
     * Created ONCE, not per access. A `get()` that wraps the SurfaceTexture
     * every time hands the player a different `Surface` object on each read
     * and leaks the previous one — and a player told to render into a surface
     * nobody holds renders into nothing.
     */
    @Volatile var filmSurface: Surface? = null
        private set
    @Volatile var cameraSurface: Surface? = null
        private set

    var layoutShowsCamera = true
    var filmAspect = 16f / 9f
    var cameraAspect = 4f / 3f

    private var encoder: StudioVideoEncoder? = null
    private var gl: StudioGl? = null
    private var program: StudioProgramGl? = null
    private var aac: StudioAacEncoder? = null
    private var publisher: RtmpPublisher? = null
    private var loop: Job? = null
    private var twitchChat: StudioChatTwitch? = null
    private var overlayForChat: ((List<ChatLine>) -> android.graphics.Bitmap)? = null
    private var chatIdsDrawn: List<String> = emptyList()

    private val running = AtomicBoolean(false)

    // ---- §6.5 thermal pressure
    //
    // Polled once a second in the render loop rather than registered as a
    // `PowerManager.OnThermalStatusChangedListener`, because the engine holds
    // no Context and the loop already wakes on that cadence. The listener
    // would arrive sooner by a fraction of a second and cost a registration
    // to leak.
    @Volatile private var qualityNote: String? = null
    /// When a transient note stops being shown; 0 = it persists (a degraded
    /// state stays up for as long as it is in effect).
    @Volatile private var qualityNoteExpiresAt: Long = 0
    @Volatile private var endedBecause: String? = null
    @Volatile private var lastThermal = -1

    // ---- §6.6 recovering a severed link
    private var supervisor: Job? = null
    @Volatile private var recovering = false
    /** Why the last §6.6 attempt failed, surfaced rather than discarded. */
    @Volatile private var reconnectFault: String? = null

    /** Polls once a second for a link that has gone, and rebuilds it. */
    private suspend fun superviseTheConnection() {
        while (running.get()) {
            kotlinx.coroutines.delay(1000)
            recoverIfSevered()
        }
    }

    /**
     * One recovery episode: attempt, back off, attempt, until the link is back
     * or the deadline passes.
     *
     * Sequential by construction — Twitch permits a single active session per
     * key and a new connection displaces the old, so overlapping attempts
     * would kick each other off.
     */
    private suspend fun recoverIfSevered() {
        val p = publisher ?: return
        if (!running.get() || recovering || !p.needsReconnect) return
        recovering = true
        try {
            val giveUpAt = System.currentTimeMillis() + (RECONNECT_DEADLINE_SECONDS * 1000).toLong()
            var attempt = 0
            while (running.get() && System.currentTimeMillis() < giveUpAt) {
                attempt += 1
                try {
                    p.reconnect()
                    reconnectFault = null
                    // The new session must OPEN on a keyframe, or a rejoining
                    // viewer and a recording server hold nothing decodable
                    // while the stream reads as live (§6.2d).
                    encoder?.requestKeyframe()
                    return
                } catch (e: Exception) {
                    // NEVER swallowed. The first version of this caught and
                    // discarded, so a NetworkOnMainThreadException on every
                    // attempt looked exactly like a link that would not come
                    // back, and logcat had nothing in it. A reconnect that
                    // cannot even be attempted must say so.
                    reconnectFault = "attempt $attempt: ${e.message ?: e.toString()}"
                    val back = RECONNECT_BACKOFF_SECONDS[
                        minOf(attempt - 1, RECONNECT_BACKOFF_SECONDS.size - 1)]
                    val remaining = giveUpAt - System.currentTimeMillis()
                    if (remaining <= 0) break
                    // Never sleep PAST the deadline, or a 15 s backoff decides
                    // when we give up instead of the rule.
                    kotlinx.coroutines.delay(minOf(back * 1000L, remaining))
                }
            }
            // The window has closed. End the show rather than hold a readout
            // saying RECONNECTING over a stream the platform finished minutes
            // ago.
            endedBecause = "the connection could not be restored within " +
                "${RECONNECT_DEADLINE_SECONDS.toInt()} seconds"
            running.set(false)
        } finally {
            recovering = false
        }
    }

    /** The one thread the GL context lives on — see the header. */
    private val renderExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "aw-studio-render").apply { priority = Thread.NORM_PRIORITY + 1 }
    }
    private val renderDispatcher = renderExecutor.asCoroutineDispatcher()

    /**
     * Builds the chain and begins rendering. [destination] may be null: the
     * engine still composites and encodes and sends nowhere, which is what
     * every platform does until a credential exists (Decision 128), and
     * `showState` reports NOT SENDING rather than pretending.
     */
    fun start(
        scope: CoroutineScope,
        destination: String? = null,
        streamKey: String = "",
        audioTap: StudioFilmAudioTap? = null,
        overlay: android.graphics.Bitmap? = null,
        /**
         * Re-renders the overlay for a given chat tail, when chat is being
         * carried. The Android overlay is ONE texture, so a new line means a
         * new bitmap and a re-upload — unlike Apple's two cached layers. The
         * surface supplies this because it owns the film's title and
         * provenance; the engine owns when to call it.
         */
        overlayForChat: ((List<ChatLine>) -> android.graphics.Bitmap)? = null,
        /** Read anonymously; no credential exists or is needed (§6.4). */
        chatChannel: String? = null,
    ) {
        if (!running.compareAndSet(false, true)) return
        if (!chatChannel.isNullOrEmpty()) {
            val chat = StudioChatTwitch()
            twitchChat = chat
            this.overlayForChat = overlayForChat
            chat.start(chatChannel)
        }
        loop = scope.launch(renderDispatcher) { runLoop(destination, streamKey, audioTap, overlay) }
        // §6.6 on its OWN coroutine, and NOT on `renderDispatcher`.
        //
        // The backoff sleeps for up to fifteen seconds at a time, and the
        // render dispatcher is a single thread that the whole composite,
        // encode and display path runs on — recovering there would freeze the
        // picture for exactly as long as it waited. The Swift side keeps them
        // apart for the same reason.
        if (destination != null) {
            // Dispatchers.IO, NOT the caller's scope.
            //
            // The caller is a Compose `LaunchedEffect`, so its scope is the
            // MAIN dispatcher, and `reconnect()` does blocking socket I/O —
            // which Android answers with NetworkOnMainThreadException. Found on
            // a Google TV (2026-09-17): the device published fine, the link was
            // severed, and the stream never came back, while the JVM test
            // passed because it called `reconnect()` from its own thread and
            // so never exercised this dispatcher at all.
            supervisor = scope.launch(kotlinx.coroutines.Dispatchers.IO) {
                superviseTheConnection()
            }
        }
    }

    private suspend fun runLoop(
        destination: String?, streamKey: String,
        audioTap: StudioFilmAudioTap?, overlay: android.graphics.Bitmap?,
    ) {
        val enc = StudioVideoEncoder(width, height, frameRate, videoBitrate).also { it.start() }
        encoder = enc
        val g = StudioGl(enc.inputSurface).also { it.setUp() }
        gl = g
        val pg = StudioProgramGl(width, height).also { it.setUp() }
        program = pg
        filmSurface = pg.filmSurfaceTexture?.let { Surface(it) }
        cameraSurface = pg.cameraSurfaceTexture?.let { Surface(it) }
        overlay?.let { pg.setOverlayBitmap(it) }

        // THE SHOW'S CLOCK — one origin, both tracks.
        //
        // Video used to be stamped `frame * 1s / frameRate`: a FRAME COUNTER,
        // which advances 1/30 s per RENDERED frame rather than per elapsed
        // second. Audio is stamped from its sample count, which tracks real
        // time exactly. So whenever the renderer misses the nominal rate — and
        // this Google TV needs 37.4 ms a frame against a 33.3 ms budget
        // (Decision 129) — video time runs SLOW and the gap against audio
        // grows without bound. Measured at +19.6 s on a 75-second broadcast.
        // Both clocks now count real nanoseconds from this instant.
        val showStartNanos = System.nanoTime()
        // §9.tt: WHERE do the seconds before the first published packet go?
        // Four candidates (film buffering, the 3-frame warm-up, the encoder's
        // avcC, the AAC config) and no evidence which dominates.
        fun mark(what: String) {
            if (BuildConfig.DEBUG) android.util.Log.i("AWSTUDIOSTART",
                String.format("%7.3f s  %s", (System.nanoTime() - showStartNanos) / 1e9, what))
        }
        mark("run loop begins")
        var frame = 0L
        var renderTotalNanos = 0L
        var lastSecond = System.currentTimeMillis()
        // DEBUG frame-budget breakdown (§9.rr). The dongle delivers 10.5 fps
        // and the loop has five phases; a total tells you nothing about which
        // one owns the time. Reset every second, logged only in a debug build.
        var renderSecNanos = 0L
        var drainSecNanos = 0L
        var audioSecNanos = 0L
        var chatSecNanos = 0L
        var frameAtLastSecond = 0L
        var leadApplied = false
        // The RTMP handshake runs OFF the render thread (§9.ss). It is a TCP
        // connect plus four AMF round trips, and on the render thread it
        // measured 2.3 SECONDS with fps=1 — every broadcast opened stalled,
        // and a handshake has no business on the thread that owns GL.
        val publishInFlight = java.util.concurrent.atomic.AtomicBoolean(false)
        val publishDone = java.util.concurrent.atomic.AtomicReference<Pair<RtmpPublisher, Boolean>?>(null)
        var filmAtLastSecond = 0
        var encodedAtLastSecond = 0L
        var encodedTotal = 0L
        var published: RtmpPublisher? = null
        // A film with no audio track would otherwise hold the broadcast
        // forever waiting for a config that will never come. After this, the
        // show goes out video-only and stays that way.
        val audioDeadline = System.currentTimeMillis() + 8_000

        // Wait for the film before publishing: a broadcast that opens on
        // nothing is a broadcast of nothing, and the first frames are what a
        // joining viewer sees.
        var markedFirstFilm = false
        while (running.get() && pg.framesAvailable.get() < 3) {
            if (!markedFirstFilm && pg.framesAvailable.get() > 0) {
                markedFirstFilm = true; mark("first film frame")
            }
            drawOnce(g, pg, frame++, renderStart = System.nanoTime(),
                     showStartNanos = showStartNanos).let { renderTotalNanos += it }
            enc.drain { _, _, _ -> }
            kotlinx.coroutines.delay(16)
        }

        mark("3 film frames — warm-up done")

        var markedAvcc = false
        var markedPcm = false
        var markedAsc = false
        while (running.get()) {
            val t0 = System.nanoTime()
            if (!markedAvcc && enc.avcC != null) { markedAvcc = true; mark("encoder avcC ready") }
            if (!markedPcm && (audioTap?.sampleRate ?: 0) > 0) { markedPcm = true; mark("first film PCM") }
            if (!markedAsc && aac?.asc != null) { markedAsc = true; mark("AAC config ready") }
            val drawn = drawOnce(g, pg, frame, t0, showStartNanos)
            renderTotalNanos += drawn
            renderSecNanos += drawn
            frame++

            // The AAC encoder is built as soon as the tap knows the film's
            // real rate — BEFORE the publish decision below, which depends on
            // whether it has produced a config yet.
            if (audioTap != null && aac == null && audioTap.sampleRate > 0) {
                aac = StudioAacEncoder(audioTap.sampleRate, audioTap.channelCount).also {
                    // Built when the first PCM arrives, which is AFTER the show
                    // began — so its sample clock is placed on the show's
                    // timeline rather than starting again at zero.
                    it.startOffsetUs = (System.nanoTime() - showStartNanos) / 1000
                    it.start()
                }
                audioTap.onPcm = { pcm, _, _ -> aac?.encode(pcm) }
            }
            val audioAt = System.nanoTime()
            aac?.drain { a, ts -> published?.sendAudio(a, ts) }
            audioSecNanos += System.nanoTime() - audioAt

            // PUBLISH ONLY WHEN EVERY TRACK IT WILL EVER CARRY IS KNOWN.
            //
            // The first assembled run published video-only because the AAC
            // config had not arrived yet, then began sending audio a second
            // later — and mediamtx closed the connection with "received a
            // packet for audio track 0, but track is not set up". A stream's
            // tracks are declared once, at publish; a track that shows up
            // afterwards is not a late track, it is a protocol error.
            // THE SINK LEAD, applied before a single audio frame is SENT.
            //
            // Adding it later would step the audio timeline mid-stream, which
            // is the one thing a live timeline must never do. Applying it here
            // is safe because nothing is published yet: frames drained before
            // the publish are dropped (`published` is null), so the first frame
            // that actually goes out already carries the corrected offset.
            if (!leadApplied) {
                val lead = audioLeadUs()
                if (lead > 0) aac?.let { it.startOffsetUs += lead; leadApplied = true }
            }
            val audioReady = audioTap == null || aac?.asc != null ||
                             System.currentTimeMillis() > audioDeadline
            // Wait for a lead sample the way we wait for the AAC config — with
            // the same deadline, so a pipeline that never reports one still
            // goes out (uncorrected) rather than never going out at all.
            val leadReady = audioTap == null || leadApplied ||
                            System.currentTimeMillis() > audioDeadline
            if (published == null && destination != null && enc.avcC != null && audioReady &&
                leadReady &&
                publishInFlight.compareAndSet(false, true)) {
                // Everything the handshake needs is captured HERE, on the
                // render thread, so the worker touches no engine state.
                val asc = aac?.asc
                val cfg = RtmpStreamConfig(width, height, frameRate.toDouble(), videoBitrate,
                    enc.avcC!!,
                    audioTap?.sampleRate ?: 44100,
                    audioTap?.channelCount ?: 2,
                    128_000, asc ?: ByteArray(0))
                val declaredAudio = asc != null
                Thread {
                    val p = RtmpPublisher()
                    // §6.4a: the cap is a LATENCY budget, so it can only be
                    // computed from this show's bitrates.
                    p.setQueueBudget(videoBitrate, 128_000)
                    try {
                        p.publish(destination, streamKey, cfg, declareAudio = declaredAudio)
                        publishDone.set(p to declaredAudio)
                    } catch (e: Exception) {
                        health = health.copy(publisher = p.health.copy(lastError = e.message))
                        // Let the next iteration try again rather than
                        // stranding the show with no destination for ever.
                        publishInFlight.set(false)
                    }
                }.apply { isDaemon = true; name = "aw-rtmp-publish"; start() }
                mark("handshake started")
            }
            // Adopt a finished handshake on the RENDER thread: `published` is
            // read by the drain below and by the per-second block, and the
            // keyframe request belongs with the adoption rather than with the
            // socket.
            publishDone.getAndSet(null)?.let { (p, declaredAudio) ->
                // A broadcast must BEGIN with a keyframe, or a joining viewer
                // has nothing decodable (§6.2d).
                enc.requestKeyframe()
                published = p; publisher = p
                // If we went out without an audio track, stop feeding the
                // encoder: sending audio to a stream that never declared it is
                // what closed the first run's connection.
                if (!declaredAudio) { audioTap?.onPcm = null; aac?.stop(); aac = null }
                mark("PUBLISHING (audio declared=" + declaredAudio + ")")
            }
            val drainAt = System.nanoTime()
            enc.drain { avcc, key, ts ->
                encodedTotal++
                published?.sendVideo(avcc, key, ts, ts)
            }
            drainSecNanos += System.nanoTime() - drainAt

            val now = System.currentTimeMillis()
            if (now - lastSecond >= 1000) {
                // Chat the program CARRIES. Re-rendered and re-uploaded only
                // when the line ids change: once a second is cheap, every
                // frame is what the overlay cache exists to avoid (§9).
                // Safe here because this block runs on the render thread,
                // which is the only thread allowed to touch GL.
                val chatAt = System.nanoTime()
                val chat = twitchChat
                val factory = overlayForChat
                if (chat != null && factory != null) {
                    val tail = chat.snapshot().takeLast(8)
                    val ids = tail.map { it.id }
                    if (ids.isNotEmpty() && ids != chatIdsDrawn) {
                        pg.setOverlayBitmap(factory(tail))
                        chatIdsDrawn = ids
                    }
                }
                chatSecNanos += System.nanoTime() - chatAt

                val film = pg.framesAvailable.get()

                // §6.5. Android reports more states than Apple: SEVERE (3) is
                // "severe throttling where UX is largely impacted", which is
                // the counterpart of Apple's `.serious`; CRITICAL (4) and
                // above are where the platform starts shutting things down,
                // so that is where the show ends.
                if (qualityNoteExpiresAt != 0L && System.currentTimeMillis() > qualityNoteExpiresAt) {
                    qualityNote = null
                    qualityNoteExpiresAt = 0
                }
                val thermal = thermalStatus()
                if (thermal != lastThermal) {
                    lastThermal = thermal
                    // The DECISION is a pure function (below) so it can be
                    // tested without GL or MediaCodec; this is only the
                    // wiring. The loop calls it — it is not a second copy of
                    // the policy, which is how §6.3's idle timer came to be
                    // implemented in a harness and nowhere else.
                    when (thermalAction(thermal, encoder?.currentBitrate ?: videoBitrate, videoBitrate)) {
                        ThermalAction.END_SHOW -> {
                            endedBecause = "the device became too hot to keep broadcasting"
                            running.set(false)
                        }
                        ThermalAction.STEP_DOWN -> {
                            val stepped = steppedBitrate(videoBitrate)
                            encoder?.setBitrate(stepped)
                            qualityNoteExpiresAt = 0
                            qualityNote = "The device is running hot, so the picture is being sent at " +
                                "${stepped / 1000} kbps instead of ${videoBitrate / 1000} kbps."
                        }
                        ThermalAction.RESTORE -> {
                            encoder?.setBitrate(videoBitrate)
                            qualityNote = "Back to full quality ${videoBitrate / 1000} kbps."
                            // The good news is an announcement; a degraded
                            // state is not. Given an expiry rather than a
                            // coroutine: this runs inside the render loop,
                            // which has no scope to launch from, and a
                            // timestamp cannot leak a task either.
                            qualityNoteExpiresAt = System.currentTimeMillis() + 8_000
                        }
                        ThermalAction.NONE -> {}
                    }
                }

                health = StudioHealth(
                    isRunning = true,
                    programFramesRendered = frame,
                    programFramesEncoded = encodedTotal,
                    filmFramesPerSecond = film - filmAtLastSecond,
                    encodedFramesPerSecond = (encodedTotal - encodedAtLastSecond).toInt(),
                    averageRenderMillis = renderTotalNanos / 1_000_000.0 / frame.coerceAtLeast(1),
                    hasDestination = published != null,
                    thermalStatus = thermal,
                    videoBitrateNow = encoder?.currentBitrate ?: videoBitrate,
                    qualityNote = qualityNote,
                    endedReason = endedBecause,
                    reconnectFault = reconnectFault,
                    publisher = published?.health ?: RtmpHealth(),
                )
                if (BuildConfig.DEBUG) {
                    val fr = (frame - frameAtLastSecond).coerceAtLeast(1)
                    android.util.Log.i("AWSTUDIOPERF", String.format(
                        "fps=%d  per-frame draw=%.1f drain=%.1f audio=%.1f  chat/s=%.1f  ms",
                        frame - frameAtLastSecond,
                        renderSecNanos / 1e6 / fr,
                        drainSecNanos / 1e6 / fr,
                        audioSecNanos / 1e6 / fr,
                        chatSecNanos / 1e6))
                }
                if (BuildConfig.DEBUG) {
                    val fr2 = (frame - frameAtLastSecond).coerceAtLeast(1)
                    android.util.Log.i("AWSTUDIOPERF", String.format(
                        "   draw split: tex=%.1f gl=%.1f swapEnc=%.1f swapDisp=%.1f ms/frame",
                        phaseTexNanos / 1e6 / fr2, phaseDrawNanos / 1e6 / fr2,
                        phaseSwapNanos / 1e6 / fr2, phaseDisplayNanos / 1e6 / fr2))
                }
                phaseTexNanos = 0; phaseDrawNanos = 0; phaseSwapNanos = 0; phaseDisplayNanos = 0
                renderSecNanos = 0; drainSecNanos = 0; audioSecNanos = 0; chatSecNanos = 0
                frameAtLastSecond = frame
                filmAtLastSecond = film
                encodedAtLastSecond = encodedTotal
                lastSecond = now
            }
            // Pace to the frame rate. A tighter loop only burns battery: the
            // encoder cannot take frames faster than it encodes them.
            //
            // MEASURED, after replacing this with a "sleep only the remainder"
            // scheme on the theory that a flat 33 ms was being ADDED to the
            // work: fps did not move (12-13 either way) and `draw` expanded
            // from ~27 ms to ~65 ms, absorbing exactly what the sleep had
            // been. `eglSwapBuffers` blocks on the encoder's surface queue, so
            // the loop already runs at the encoder's pace and the sleep was
            // never additive. The comment above was right; the change was
            // reverted (§9.rr).
            kotlinx.coroutines.delay((1000L / frameRate).coerceAtLeast(1))
        }
        // A handshake that completed after the show ended owns a live socket
        // that nothing else will ever close.
        publishDone.getAndSet(null)?.first?.close()
    }

    // §9.uu phase accounting, reset by the per-second block.
    private var phaseTexNanos = 0L
    private var phaseDrawNanos = 0L
    private var phaseSwapNanos = 0L
    private var phaseDisplayNanos = 0L

    private fun drawOnce(g: StudioGl, pg: StudioProgramGl, frame: Long, renderStart: Long,
                         showStartNanos: Long): Long {
        // The newest frames are pulled ONCE, on the encoder pass, and the
        // display pass reuses them: `updateTexImage` twice in a frame would
        // consume two decoded frames to show one.
        g.makeCurrent()
        val texAt = System.nanoTime()
        pg.updateFilmFrame()
        if (layoutShowsCamera) pg.updateCameraFrame()
        phaseTexNanos += System.nanoTime() - texAt
        val drawAt = System.nanoTime()
        drawProgram(pg)
        phaseDrawNanos += System.nanoTime() - drawAt
        // The suspected blocker: eglSwapBuffers on the ENCODER surface waits
        // for a free input buffer, so this is where the encoder's throughput
        // shows up as if it were render cost (§9.rr).
        val swapAt = System.nanoTime()
        g.swap(System.nanoTime() - showStartNanos)
        phaseSwapNanos += System.nanoTime() - swapAt

        // ...and again for the host's screen (§6.2j). A pending surface is
        // attached here rather than from whatever thread handed it over: an
        // EGL surface belongs to the context's thread like everything else.
        if (displayDirty) {
            displayDirty = false
            g.attachDisplay(pendingDisplaySurface)
        }
        if (g.hasDisplay && g.makeCurrentDisplay()) {
            drawProgram(pg)
            val dispAt = System.nanoTime()
            g.swapDisplay()
            phaseDisplayNanos += System.nanoTime() - dispAt
            g.makeCurrent()
        }
        return System.nanoTime() - renderStart
    }

    private fun drawProgram(pg: StudioProgramGl) {
        gl?.clear(0f, 0f, 0f)
        pg.drawFilm(filmAspect)
        // A tile is drawn only when a camera has ACTUALLY delivered a frame.
        // `layoutShowsCamera` is the host's intent; this is the fact. Drawing
        // the tile on intent alone puts an empty black rectangle over the film
        // on every device without a camera — which is every television (§9.6),
        // and is what it did before this check (seen on a Google TV).
        if (layoutShowsCamera && pg.cameraFramesAvailable.get() > 0) {
            pg.drawCameraCorner(cameraAspect)
        }
        pg.drawOverlay()
    }

    /**
     * The surface the HOST sees — a `SurfaceView` the player screen owns.
     * Handed over from the UI thread and picked up by the render thread,
     * because an EGL surface may only be created on the context's thread.
     * Pass null to detach when the view goes away.
     */
    fun setDisplaySurface(surface: Surface?) {
        pendingDisplaySurface = surface
        // A separate flag rather than a sentinel Surface: null is a MEANINGFUL
        // value here (detach), and manufacturing a placeholder `Surface` to
        // represent it would allocate a real SurfaceTexture at class-init on
        // every device that ever loads this file.
        displayDirty = true
    }

    @Volatile private var pendingDisplaySurface: Surface? = null
    @Volatile private var displayDirty = false

    suspend fun stop() {
        // NOT `compareAndSet(true, false)`: §6.5's critical path ends the loop
        // from INSIDE it by clearing `running`, and the old guard then made
        // stop() a no-op — leaving the encoder, the publisher, both surfaces
        // and the GL context alive after the show had ended. Calling stop()
        // from the loop instead would deadlock on the join below.
        val wasRunning = running.getAndSet(false)
        if (!wasRunning && loop == null) return
        supervisor?.cancel(); supervisor = null
        twitchChat?.stop(); twitchChat = null
        overlayForChat = null
        loop?.join(); loop = null
        publisher?.close(); publisher = null
        aac?.stop(); aac = null
        filmSurface?.release(); filmSurface = null
        cameraSurface?.release(); cameraSurface = null
        program?.tearDown(); program = null
        gl?.tearDown(); gl = null
        encoder?.stop(); encoder = null
        // The reason OUTLIVES the reset: a surface that draws an end card reads
        // it after the engine has stopped, and a cleared reason is a frozen
        // frame with no explanation.
        health = StudioHealth(endedReason = endedBecause)
        renderExecutor.shutdown()
    }

    companion object {
        /** `PowerManager.THERMAL_STATUS_SEVERE`, named rather than inlined. */
        const val THERMAL_SEVERE = 3
        /** THERMAL_STATUS_CRITICAL; EMERGENCY and SHUTDOWN are above it. */
        const val THERMAL_CRITICAL = 4
        /** §6.5, the same fraction the Swift engine uses. */
        const val SEVERE_BITRATE_FRACTION = 0.6

        /**
         * §6.6's schedule. The same numbers as Swift's
         * `RTMPReconnectPolicy`, matched to the ingests' own grace windows:
         * Mux's reconnect window defaults to 60 s at standard latency and
         * YouTube holds a broadcast open roughly a minute or two, so past the
         * deadline there is usually nothing left to reconnect TO.
         */
        val RECONNECT_BACKOFF_SECONDS = listOf(1L, 2L, 4L, 8L, 15L)
        const val RECONNECT_DEADLINE_SECONDS = 60.0

        fun steppedBitrate(configured: Int) = (configured * SEVERE_BITRATE_FRACTION).toInt()

        /**
         * §6.5's decision, as a pure function.
         *
         * Extracted so it can be tested at all: the loop that applies it needs
         * a GL context and a MediaCodec, so the policy would otherwise only
         * ever run on a device and never be checked against its own rule.
         *
         * `END_SHOW` above SEVERE is deliberate and is not a quality step:
         * Android's CRITICAL, EMERGENCY and SHUTDOWN are where the platform
         * itself starts stopping things, and an end card the audience sees
         * beats a frozen frame left by a process the system killed.
         */
        fun thermalAction(status: Int, currentBitrate: Int, configuredBitrate: Int): ThermalAction = when {
            status >= THERMAL_CRITICAL -> ThermalAction.END_SHOW
            status == THERMAL_SEVERE ->
                // Idempotent: re-applying the step every second would be a
                // pointless `setParameters` call and a repeated note.
                if (currentBitrate == steppedBitrate(configuredBitrate)) ThermalAction.NONE
                else ThermalAction.STEP_DOWN
            else ->
                if (currentBitrate != configuredBitrate) ThermalAction.RESTORE else ThermalAction.NONE
        }
    }
}
