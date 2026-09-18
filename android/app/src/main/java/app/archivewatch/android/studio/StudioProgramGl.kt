package app.archivewatch.android.studio

// The program renderer for Android (docs/WATCH-TOGETHER.md §6.2) — the GLES
// counterpart of the Apple side's Core Image `ProgramRenderer`.
//
// The film arrives as an EXTERNAL OES texture, which is the only way a video
// decoder's output can be sampled without a copy: ExoPlayer renders into a
// `SurfaceTexture`, the texture is bound as `GL_TEXTURE_EXTERNAL_OES`, and
// this shader draws it into the encoder's input surface. Two consequences
// that are easy to get wrong and silent when you do:
//
//   · an external texture needs its OWN sampler type (`samplerExternalOES`)
//     and the `GL_OES_EGL_image_external` extension declared in the shader. A
//     plain `sampler2D` compiles and samples nothing.
//   · `SurfaceTexture.getTransformMatrix` is NOT optional. Decoders hand back
//     frames with their own orientation and crop, and ignoring the matrix
//     gives a picture that is upside down, mirrored, or subtly cropped —
//     which looks like a bad camera rather than a bug.
//
// Aspect-fit is done in the VERTICES rather than the texture coordinates, so
// the film keeps its shape and the surround stays the clear colour — the same
// rule as §3.3 on Apple ("a hero never reshapes its art" is the same instinct,
// Decision 097).

import android.graphics.SurfaceTexture
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

class StudioProgramGl(private val programWidth: Int, private val programHeight: Int) {

    private var program = 0
    private var aPosition = 0
    private var aTexCoord = 0
    private var uTexMatrix = 0
    private var uVertexMatrix = 0
    private var uTexture = 0

    /** The texture ExoPlayer renders into. Valid after [setUp]. */
    var filmTextureId = 0
        private set
    var filmSurfaceTexture: SurfaceTexture? = null
        private set

    /**
     * New frames the producer has actually delivered.
     *
     * `updateTexImage()` does NOT fail when there is nothing new — it
     * re-presents the previous frame — so its success is not evidence that a
     * film is playing. Only the callback is.
     */
    val framesAvailable = java.util.concurrent.atomic.AtomicInteger(0)

    private val texMatrix = FloatArray(16)
    private val vertexMatrix = FloatArray(16)
    private lateinit var vertices: FloatBuffer
    private lateinit var texCoords: FloatBuffer

    fun setUp() {
        program = buildProgram(VERTEX_SHADER, FRAGMENT_SHADER_OES)
        aPosition = GLES20.glGetAttribLocation(program, "aPosition")
        aTexCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
        uTexMatrix = GLES20.glGetUniformLocation(program, "uTexMatrix")
        uVertexMatrix = GLES20.glGetUniformLocation(program, "uVertexMatrix")
        uTexture = GLES20.glGetUniformLocation(program, "sTexture")

        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        filmTextureId = ids[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, filmTextureId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                               GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                               GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                               GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                               GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        filmSurfaceTexture = SurfaceTexture(filmTextureId).apply {
            // WITHOUT THIS THE PICTURE IS BLACK. A SurfaceTexture that is not
            // attached to a View has no size of its own, so the producer —
            // here ExoPlayer's decoder — renders into a default buffer that is
            // not the film. Everything else succeeds: frames arrive,
            // updateTexImage works, the encoder encodes, the server accepts
            // the stream. Seen on a Google TV, 2026-09-17: a perfectly healthy
            // broadcast of nothing.
            setDefaultBufferSize(programWidth, programHeight)
            // An explicit Handler, because the no-Handler overload needs a
            // Looper on the CALLING thread and a render thread has none — the
            // callback then never fires and "no frames" is indistinguishable
            // from a film that will not play.
            setOnFrameAvailableListener({ framesAvailable.incrementAndGet() },
                                        android.os.Handler(android.os.Looper.getMainLooper()))
        }

        vertices = floatBuffer(floatArrayOf(-1f, -1f,  1f, -1f,  -1f, 1f,  1f, 1f))
        texCoords = floatBuffer(floatArrayOf(0f, 0f,  1f, 0f,  0f, 1f,  1f, 1f))
        Matrix.setIdentityM(texMatrix, 0)
        Matrix.setIdentityM(vertexMatrix, 0)
    }

    /**
     * Pulls the newest decoded frame, if there is one. MUST run on the thread
     * holding the GL context — `updateTexImage` binds to the current context
     * and throws from anywhere else.
     */
    fun updateFilmFrame(): Boolean {
        val st = filmSurfaceTexture ?: return false
        return try {
            st.updateTexImage()
            st.getTransformMatrix(texMatrix)
            true
        } catch (_: Exception) { false }
    }

    /**
     * Draws the film aspect-fit into the program frame.
     * @param filmAspect width/height of the film as it should appear.
     */
    fun drawFilm(filmAspect: Float) {
        val programAspect = programWidth.toFloat() / programHeight
        // Scale the QUAD, not the texture: letterbox or pillarbox, never
        // stretch. The unfilled surround keeps whatever was cleared.
        var sx = 1f; var sy = 1f
        if (filmAspect > programAspect) sy = programAspect / filmAspect
        else sx = filmAspect / programAspect
        Matrix.setIdentityM(vertexMatrix, 0)
        Matrix.scaleM(vertexMatrix, 0, sx, sy, 1f)

        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, filmTextureId)
        GLES20.glUniform1i(uTexture, 0)
        GLES20.glUniformMatrix4fv(uTexMatrix, 1, false, texMatrix, 0)
        GLES20.glUniformMatrix4fv(uVertexMatrix, 1, false, vertexMatrix, 0)
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 0, vertices)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 0, texCoords)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)
    }

    fun tearDown() {
        filmSurfaceTexture?.release(); filmSurfaceTexture = null
        if (filmTextureId != 0) GLES20.glDeleteTextures(1, intArrayOf(filmTextureId), 0)
        if (program != 0) GLES20.glDeleteProgram(program)
    }

    companion object {
        private const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec4 aTexCoord;
            uniform mat4 uTexMatrix;
            uniform mat4 uVertexMatrix;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = uVertexMatrix * aPosition;
                vTexCoord = (uTexMatrix * aTexCoord).xy;
            }
        """

        /** `samplerExternalOES`, not `sampler2D` — see the header. */
        private const val FRAGMENT_SHADER_OES = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vTexCoord;
            uniform samplerExternalOES sTexture;
            void main() { gl_FragColor = texture2D(sTexture, vTexCoord); }
        """

        private fun floatBuffer(values: FloatArray): FloatBuffer =
            ByteBuffer.allocateDirect(values.size * 4).order(ByteOrder.nativeOrder())
                .asFloatBuffer().apply { put(values); position(0) }

        private fun buildProgram(vs: String, fs: String): Int {
            val v = compile(GLES20.GL_VERTEX_SHADER, vs)
            val f = compile(GLES20.GL_FRAGMENT_SHADER, fs)
            val p = GLES20.glCreateProgram()
            GLES20.glAttachShader(p, v); GLES20.glAttachShader(p, f)
            GLES20.glLinkProgram(p)
            val status = IntArray(1)
            GLES20.glGetProgramiv(p, GLES20.GL_LINK_STATUS, status, 0)
            check(status[0] == GLES20.GL_TRUE) { "link failed: ${GLES20.glGetProgramInfoLog(p)}" }
            return p
        }

        private fun compile(type: Int, source: String): Int {
            val s = GLES20.glCreateShader(type)
            GLES20.glShaderSource(s, source)
            GLES20.glCompileShader(s)
            val status = IntArray(1)
            GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, status, 0)
            // Report the log: a shader that fails to compile otherwise draws
            // nothing, silently, which is indistinguishable from a black film.
            check(status[0] == GLES20.GL_TRUE) { "shader compile failed: ${GLES20.glGetShaderInfoLog(s)}" }
            return s
        }
    }
}
