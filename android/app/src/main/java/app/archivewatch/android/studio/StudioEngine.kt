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
    val publisher: RtmpHealth = RtmpHealth(),
) {
    /** What the SHOW is doing, in the host's terms — not the transport's. */
    val showState: String get() = when {
        !isRunning -> "OFF"
        filmFramesPerSecond > 0 && encodedFramesPerSecond == 0 -> "STOPPED"
        publisher.lastError != null -> "OFFLINE"
        !hasDestination -> "NOT SENDING"
        publisher.state == "publishing" -> "LIVE"
        else -> "CONNECTING"
    }

    val problem: String? get() = when (showState) {
        "STOPPED" -> "The picture has stopped being encoded — your audience is not receiving the show."
        "NOT SENDING" -> "The show is being made but not sent anywhere — no destination is set."
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
    private val running = AtomicBoolean(false)

    // ---- §6.5 thermal pressure
    //
    // Polled once a second in the render loop rather than registered as a
    // `PowerManager.OnThermalStatusChangedListener`, because the engine holds
    // no Context and the loop already wakes on that cadence. The listener
    // would arrive sooner by a fraction of a second and cost a registration
    // to leak.
    @Volatile private var qualityNote: String? = null
    @Volatile private var endedBecause: String? = null
    @Volatile private var lastThermal = -1

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
    ) {
        if (!running.compareAndSet(false, true)) return
        loop = scope.launch(renderDispatcher) { runLoop(destination, streamKey, audioTap, overlay) }
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

        var frame = 0L
        var renderTotalNanos = 0L
        var lastSecond = System.currentTimeMillis()
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
        while (running.get() && pg.framesAvailable.get() < 3) {
            drawOnce(g, pg, frame++, renderStart = System.nanoTime()).let { renderTotalNanos += it }
            enc.drain { _, _, _ -> }
            kotlinx.coroutines.delay(16)
        }

        while (running.get()) {
            val t0 = System.nanoTime()
            renderTotalNanos += drawOnce(g, pg, frame, t0)
            frame++

            // The AAC encoder is built as soon as the tap knows the film's
            // real rate — BEFORE the publish decision below, which depends on
            // whether it has produced a config yet.
            if (audioTap != null && aac == null && audioTap.sampleRate > 0) {
                aac = StudioAacEncoder(audioTap.sampleRate, audioTap.channelCount).also { it.start() }
                audioTap.onPcm = { pcm, _, _ -> aac?.encode(pcm) }
            }
            aac?.drain { a, ts -> published?.sendAudio(a, ts) }

            // PUBLISH ONLY WHEN EVERY TRACK IT WILL EVER CARRY IS KNOWN.
            //
            // The first assembled run published video-only because the AAC
            // config had not arrived yet, then began sending audio a second
            // later — and mediamtx closed the connection with "received a
            // packet for audio track 0, but track is not set up". A stream's
            // tracks are declared once, at publish; a track that shows up
            // afterwards is not a late track, it is a protocol error.
            val audioReady = audioTap == null || aac?.asc != null ||
                             System.currentTimeMillis() > audioDeadline
            if (published == null && destination != null && enc.avcC != null && audioReady) {
                val asc = aac?.asc
                val p = RtmpPublisher()
                // §6.4a: the cap is a LATENCY budget, so it can only be
                // computed from this show's bitrates.
                p.setQueueBudget(videoBitrate, 128_000)
                try {
                    p.publish(destination, streamKey,
                        RtmpStreamConfig(width, height, frameRate.toDouble(), videoBitrate,
                            enc.avcC!!,
                            audioTap?.sampleRate ?: 44100,
                            audioTap?.channelCount ?: 2,
                            128_000, asc ?: ByteArray(0)),
                        declareAudio = asc != null)
                    // A broadcast must BEGIN with a keyframe, or a joining
                    // viewer has nothing decodable (§6.2d).
                    enc.requestKeyframe()
                    published = p; publisher = p
                    // If we went out without an audio track, stop feeding the
                    // encoder: sending audio to a stream that never declared
                    // it is what closed the first run's connection.
                    if (asc == null) { audioTap?.onPcm = null; aac?.stop(); aac = null }
                } catch (e: Exception) {
                    health = health.copy(publisher = p.health.copy(lastError = e.message))
                }
            }
            enc.drain { avcc, key, ts ->
                encodedTotal++
                published?.sendVideo(avcc, key, ts, ts)
            }

            val now = System.currentTimeMillis()
            if (now - lastSecond >= 1000) {
                val film = pg.framesAvailable.get()

                // §6.5. Android reports more states than Apple: SEVERE (3) is
                // "severe throttling where UX is largely impacted", which is
                // the counterpart of Apple's `.serious`; CRITICAL (4) and
                // above are where the platform starts shutting things down,
                // so that is where the show ends.
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
                            qualityNote = "The device is running hot, so the picture is being sent at " +
                                "${stepped / 1000} kbps instead of ${videoBitrate / 1000} kbps."
                        }
                        ThermalAction.RESTORE -> {
                            encoder?.setBitrate(videoBitrate)
                            qualityNote = "Back to full quality ${videoBitrate / 1000} kbps."
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
                    publisher = published?.health ?: RtmpHealth(),
                )
                filmAtLastSecond = film
                encodedAtLastSecond = encodedTotal
                lastSecond = now
            }
            // Pace to the frame rate. A tighter loop only burns battery: the
            // encoder cannot take frames faster than it encodes them.
            kotlinx.coroutines.delay((1000L / frameRate).coerceAtLeast(1))
        }
    }

    private fun drawOnce(g: StudioGl, pg: StudioProgramGl, frame: Long, renderStart: Long): Long {
        // The newest frames are pulled ONCE, on the encoder pass, and the
        // display pass reuses them: `updateTexImage` twice in a frame would
        // consume two decoded frames to show one.
        g.makeCurrent()
        pg.updateFilmFrame()
        if (layoutShowsCamera) pg.updateCameraFrame()
        drawProgram(pg)
        g.swap(frame * 1_000_000_000L / frameRate)

        // ...and again for the host's screen (§6.2j). A pending surface is
        // attached here rather than from whatever thread handed it over: an
        // EGL surface belongs to the context's thread like everything else.
        if (displayDirty) {
            displayDirty = false
            g.attachDisplay(pendingDisplaySurface)
        }
        if (g.hasDisplay && g.makeCurrentDisplay()) {
            drawProgram(pg)
            g.swapDisplay()
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
