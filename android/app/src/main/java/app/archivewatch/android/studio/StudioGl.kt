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

        surface = EGL14.eglCreateWindowSurface(
            display, configs[0], target, intArrayOf(EGL14.EGL_NONE), 0)
        check(surface != EGL14.EGL_NO_SURFACE) { "eglCreateWindowSurface failed" }
        makeCurrent()
    }

    fun makeCurrent() {
        check(EGL14.eglMakeCurrent(display, surface, surface, context)) { "eglMakeCurrent failed" }
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
