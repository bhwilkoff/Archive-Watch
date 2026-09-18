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
) {
    @Volatile var health = StudioHealth(); private set

    /** The surface the film's player renders into. Valid once [start] returns. */
    val filmSurface: Surface? get() = program?.filmSurfaceTexture?.let { Surface(it) }
    val cameraSurface: Surface? get() = program?.cameraSurfaceTexture?.let { Surface(it) }

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
                health = StudioHealth(
                    isRunning = true,
                    programFramesRendered = frame,
                    programFramesEncoded = encodedTotal,
                    filmFramesPerSecond = film - filmAtLastSecond,
                    encodedFramesPerSecond = (encodedTotal - encodedAtLastSecond).toInt(),
                    averageRenderMillis = renderTotalNanos / 1_000_000.0 / frame.coerceAtLeast(1),
                    hasDestination = published != null,
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
        g.makeCurrent()
        pg.updateFilmFrame()
        if (layoutShowsCamera) pg.updateCameraFrame()
        g.clear(0f, 0f, 0f)
        pg.drawFilm(filmAspect)
        if (layoutShowsCamera) pg.drawCameraCorner(cameraAspect)
        pg.drawOverlay()
        g.swap(frame * 1_000_000_000L / frameRate)
        return System.nanoTime() - renderStart
    }

    suspend fun stop() {
        if (!running.compareAndSet(true, false)) return
        loop?.join(); loop = null
        publisher?.close(); publisher = null
        aac?.stop(); aac = null
        program?.tearDown(); program = null
        gl?.tearDown(); gl = null
        encoder?.stop(); encoder = null
        health = StudioHealth()
        renderExecutor.shutdown()
    }
}
