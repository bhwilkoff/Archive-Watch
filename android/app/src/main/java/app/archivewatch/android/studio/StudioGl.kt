package app.archivewatch.android.studio

// An EGL context whose surface IS the encoder's input surface
// (docs/WATCH-TOGETHER.md §6.2). Everything the program shows — the film, the
// camera tile, the overlays — is drawn here, and the GPU hands the result
// straight to MediaCodec. No readback, which is the whole reason Android can
// be cheaper than Apple at this.
//
// `presentAt` is not decoration: MediaCodec takes the frame's timestamp from
// EGL's presentation time, so a frame drawn without one is encoded with a
// timestamp of zero and the whole stream is undecodable. It is set through
// `EGLExt.eglPresentationTimeANDROID`, in NANOSECONDS, which is the only
// place in this pipeline that unit appears.

import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.view.Surface

class StudioGl(private val target: Surface) {

    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var context: EGLContext = EGL14.EGL_NO_CONTEXT
    private var surface: EGLSurface = EGL14.EGL_NO_SURFACE

    /**
     * A SECOND window surface, for what the host sees.
     *
     * THIS IS THE ANDROID/APPLE DIFFERENCE MADE CONCRETE. On Apple
     * `AVPlayerItemVideoOutput` is a TAP: the player keeps its own display and
     * the Studio reads frames beside it. On Android `Player.setVideoSurface`
     * is EXCLUSIVE — point the player at the Studio's texture and the screen
     * goes black, point it at the screen and the Studio gets nothing. The
     * first attempt did the latter and the readout honestly reported `OFF`
     * forever (§6.2j).
     *
     * So the engine draws the composed program TWICE, to two window surfaces
     * sharing ONE context: MediaCodec's input surface and the display. The
     * host then sees the PROGRAM rather than the bare film, which is what a
     * studio should show — a host watching what their audience is watching
     * cannot be surprised by it.
     */
    private var displaySurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var chosenConfig: EGLConfig? = null

    fun setUp() {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(display != EGL14.EGL_NO_DISPLAY) { "no EGL display" }
        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize failed" }

        val attribs = intArrayOf(
            EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            // EGL_RECORDABLE_ANDROID. Without it the driver may pick a config
            // the encoder cannot consume, and the failure is a black stream
            // rather than an error.
            0x3142, 1,
            EGL14.EGL_NONE
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        check(EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, numConfigs, 0)
              && numConfigs[0] > 0) { "no recordable EGL config" }

        context = EGL14.eglCreateContext(
            display, configs[0], EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
        check(context != EGL14.EGL_NO_CONTEXT) { "eglCreateContext failed" }

        chosenConfig = configs[0]
        surface = EGL14.eglCreateWindowSurface(
            display, configs[0], target, intArrayOf(EGL14.EGL_NONE), 0)
        check(surface != EGL14.EGL_NO_SURFACE) { "eglCreateWindowSurface failed" }
        makeCurrent()
    }

    fun makeCurrent() {
        check(EGL14.eglMakeCurrent(display, surface, surface, context)) { "eglMakeCurrent failed" }
        applyViewport(surface)
    }

    /**
     * THE VIEWPORT BELONGS TO THE SURFACE, NOT THE CONTEXT.
     *
     * Two window surfaces of different sizes share one context here — the
     * encoder's 1280x720 and the host's 1920x1080 — and `glViewport` is
     * context state that survives `eglMakeCurrent`. Without this the display
     * pass inherits the encoder's viewport and the whole program is drawn into
     * the bottom-left 1280x720 corner of the television, which is exactly what
     * it did (seen on a Google TV, 2026-09-17).
     */
    private fun applyViewport(s: EGLSurface) {
        val w = IntArray(1); val h = IntArray(1)
        EGL14.eglQuerySurface(display, s, EGL14.EGL_WIDTH, w, 0)
        EGL14.eglQuerySurface(display, s, EGL14.EGL_HEIGHT, h, 0)
        if (w[0] > 0 && h[0] > 0) GLES20.glViewport(0, 0, w[0], h[0])
    }

    /**
     * Point the host's screen at this context too. Safe to call again with a
     * new surface — a `SurfaceView` is destroyed and recreated whenever the
     * window changes, and holding a stale `EGLSurface` across that is a
     * black screen at best.
     */
    fun attachDisplay(displayTarget: Surface?) {
        releaseDisplaySurface()
        val cfg = chosenConfig ?: return
        if (displayTarget == null || !displayTarget.isValid) return
        displaySurface = EGL14.eglCreateWindowSurface(
            display, cfg, displayTarget, intArrayOf(EGL14.EGL_NONE), 0)
        if (displaySurface == EGL14.EGL_NO_SURFACE) displaySurface = EGL14.EGL_NO_SURFACE
    }

    val hasDisplay: Boolean get() = displaySurface != EGL14.EGL_NO_SURFACE

    fun makeCurrentDisplay(): Boolean {
        if (displaySurface == EGL14.EGL_NO_SURFACE) return false
        if (!EGL14.eglMakeCurrent(display, displaySurface, displaySurface, context)) return false
        applyViewport(displaySurface)
        return true
    }

    /** The display gets NO presentation time — it is shown, not encoded. */
    fun swapDisplay() {
        if (displaySurface != EGL14.EGL_NO_SURFACE) EGL14.eglSwapBuffers(display, displaySurface)
    }

    private fun releaseDisplaySurface() {
        if (displaySurface != EGL14.EGL_NO_SURFACE) {
            EGL14.eglMakeCurrent(display, surface, surface, context)
            EGL14.eglDestroySurface(display, displaySurface)
            displaySurface = EGL14.EGL_NO_SURFACE
        }
    }

    /** Hands the drawn frame to the encoder, stamped with its own time. */
    fun swap(presentationNanos: Long) {
        EGLExt.eglPresentationTimeANDROID(display, surface, presentationNanos)
        EGL14.eglSwapBuffers(display, surface)
    }

    /** A flat fill — the simplest thing that proves the whole chain moves. */
    fun clear(r: Float, g: Float, b: Float) {
        GLES20.glClearColor(r, g, b, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
    }

    fun tearDown() {
        releaseDisplaySurface()
        if (display != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE,
                                 EGL14.EGL_NO_CONTEXT)
            if (surface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, surface)
            if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context)
            EGL14.eglTerminate(display)
        }
        display = EGL14.EGL_NO_DISPLAY
        context = EGL14.EGL_NO_CONTEXT
        surface = EGL14.EGL_NO_SURFACE
    }
}
