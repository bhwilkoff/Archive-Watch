package app.archivewatch.android.studio

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.StreamConfigurationMap
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicInteger

/**
 * The host's camera, drawn straight into the Studio's program texture.
 *
 * WHY THIS EXISTS AT ALL. Until 2026-09-20 the Android Studio had the whole
 * RECEIVING end of a camera tile and no source for it: `StudioEngine` built a
 * `cameraSurface` from the program's `SurfaceTexture`, `drawCameraCorner` ran
 * whenever `cameraFramesAvailable > 0`, and nothing ever opened a camera, so
 * that counter was permanently 0 and the tile was never drawn. The manifest
 * did not even declare `CAMERA`. On a phone that is the whole feature — a
 * watch-along with no host is a film (WATCH-TOGETHER §9.qqqqq).
 *
 * WHY CAMERA2 AND NOT CAMERAX. This project ships zero third-party packages
 * by choice (Decision 127) and `androidx.camera` is not among its
 * dependencies. Camera2 is the platform API, costs nothing to add, and the
 * engine already hands out exactly what it wants: a `SurfaceTexture` to write
 * into. CameraX would buy lifecycle plumbing this class does not need — it is
 * opened and closed by a show, not by an Activity.
 *
 * WHAT IS SILENT WHEN WRONG, and therefore what this class is careful about:
 *
 *  - **The capture size must be one the sensor advertises.** A
 *    `SurfaceTexture` will accept any `setDefaultBufferSize`, and the camera
 *    will then quietly produce something else or nothing. `StudioProgramGl`
 *    seeds a third of the programme (640x360 at 1080p), which most sensors do
 *    not offer. The size is therefore CHOSEN from `StreamConfigurationMap`.
 *  - **The tile's shape comes from the chosen size, not from a guess.**
 *    `StudioEngine.cameraAspect` defaults to 4:3 and the renderer derives the
 *    corner tile from it, so a 16:9 sensor drawn as 4:3 is stretched. It is
 *    set from what was actually opened.
 *  - **A permission that was never granted opens nothing and throws.** The
 *    check is here rather than at the call site, because `openCamera` throws
 *    `SecurityException` and a show must not die for a camera it can do
 *    without — §8.8's rule that an absent camera is NORMAL.
 */
class StudioCamera {

    /** Frames the camera has delivered, for the readouts (§4). */
    val framesDelivered = AtomicInteger(0)

    /** Why the camera is not running, or null. Said out loud, never inferred. */
    @Volatile var problem: String? = null
        private set

    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var surface: Surface? = null
    private var thread: HandlerThread? = null
    private var handler: Handler? = null

    /** The aspect (width / height) actually opened, for `cameraAspect`. */
    @Volatile var aspect: Float = 4f / 3f

    /**
     * How far the sensor's frame must be turned to look upright, in degrees.
     *
     * Camera2 delivers frames in SENSOR orientation and nothing corrects them
     * — so a front camera on a portrait-held phone sends a sideways picture,
     * which the owner reported on 2026-09-21 as the camera looking wrong. The
     * Apple side has done this since the beginning with
     * `AVCaptureDevice.RotationCoordinator`; Android had no equivalent at all.
     *
     * The FRONT camera is also mirrored — a host watching themselves expects a
     * mirror, and so does every video-call app — but the AUDIENCE should see
     * it unmirrored, which is what the tile draws.
     */
    @Volatile var rotationDegrees: Int = 0
        private set

    /**
     * Opens the front camera onto [texture]. Returns false and sets [problem]
     * rather than throwing: a show without a host's face is a normal show.
     */
    fun open(context: Context, texture: SurfaceTexture, preferFront: Boolean = true): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED) {
            problem = "Camera permission has not been granted, so you will not be in the show."
            return false
        }
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            ?: run { problem = "This device has no camera service."; return false }

        val id = pick(manager, preferFront)
            ?: run { problem = "This device has no camera."; return false }

        val chars = manager.getCameraCharacteristics(id)
        val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            as? StreamConfigurationMap
            ?: run { problem = "This camera reports no output sizes."; return false }

        val size = chooseSize(map)
            ?: run { problem = "This camera offers no usable size."; return false }
        // The sensor's own mounting, less however the DEVICE is turned.
        val sensor = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
        val facingFront =
            chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
        rotationDegrees = if (facingFront) (sensor + 360) % 360 else (sensor + 360) % 360
        // AND THE TILE'S SHAPE TURNS WITH IT. At 90 or 270 a 1280x720 sensor
        // frame is a 720x1280 picture, and a tile sized from the raw numbers
        // would squash it — which is the half of this the aspect alone would
        // have got wrong.
        aspect = if (rotationDegrees % 180 == 90) {
            size.height.toFloat() / size.width.toFloat()
        } else {
            size.width.toFloat() / size.height.toFloat()
        }

        // SET THE SIZE ON THE TEXTURE, not merely near it. Everything
        // downstream — the tile's shape, the sampled resolution — follows from
        // this, and a texture left at the placeholder silently mismatches.
        texture.setDefaultBufferSize(size.width, size.height)
        val s = Surface(texture)
        surface = s

        val t = HandlerThread("aw-studio-camera").also { it.start() }
        thread = t
        val h = Handler(t.looper)
        handler = h

        return try {
            manager.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    device = camera
                    startRepeating(camera, s, h)
                }
                override fun onDisconnected(camera: CameraDevice) {
                    problem = "The camera was disconnected."
                    camera.close(); device = null
                }
                override fun onError(camera: CameraDevice, error: Int) {
                    // NAMED, NEVER SWALLOWED. An OSStatus thrown away is how
                    // the Apple encoder ran five minutes reporting health it
                    // did not have (§9); the same rule applies here.
                    problem = "The camera could not be opened (error $error)."
                    camera.close(); device = null
                }
            }, h)
            true
        } catch (e: SecurityException) {
            problem = "Camera permission was refused."
            false
        } catch (e: Exception) {
            problem = "The camera could not be opened: ${e.message}"
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun startRepeating(camera: CameraDevice, target: Surface, h: Handler) {
        try {
            camera.createCaptureSession(listOf(target),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(s: CameraCaptureSession) {
                        session = s
                        val req = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                        req.addTarget(target)
                        // A broadcast wants an even exposure, not a
                        // photograph's: auto everything, no flash.
                        req.set(CaptureRequest.CONTROL_MODE, CameraMetadataAuto)
                        s.setRepeatingRequest(req.build(),
                            object : CameraCaptureSession.CaptureCallback() {
                                override fun onCaptureCompleted(
                                    sess: CameraCaptureSession,
                                    request: CaptureRequest,
                                    result: android.hardware.camera2.TotalCaptureResult
                                ) { framesDelivered.incrementAndGet() }
                            }, h)
                        problem = null
                    }
                    override fun onConfigureFailed(s: CameraCaptureSession) {
                        problem = "The camera session could not be configured."
                    }
                }, h)
        } catch (e: Exception) {
            problem = "The camera session failed: ${e.message}"
        }
    }

    /** `CONTROL_MODE_AUTO`, spelled out so the import stays small. */
    private val CameraMetadataAuto = android.hardware.camera2.CameraMetadata.CONTROL_MODE_AUTO

    private fun pick(manager: CameraManager, preferFront: Boolean): String? {
        val ids = try { manager.cameraIdList } catch (e: Exception) { return null }
        if (ids.isEmpty()) return null
        val wanted = if (preferFront) CameraCharacteristics.LENS_FACING_FRONT
                     else CameraCharacteristics.LENS_FACING_BACK
        // THE HOST FACES THE PHONE, so the front camera is the default — but a
        // device with only a back camera must still work rather than refuse.
        ids.firstOrNull {
            manager.getCameraCharacteristics(it)
                .get(CameraCharacteristics.LENS_FACING) == wanted
        }?.let { return it }
        return ids.first()
    }

    /**
     * The largest advertised size at or under 1280x720.
     *
     * The tile occupies about a quarter of the programme's width, so anything
     * beyond 720p is sampled away — and a needlessly large capture costs the
     * render thread on a device whose budget §9.uu already measured as tight.
     */
    private fun chooseSize(map: StreamConfigurationMap): Size? {
        val sizes = map.getOutputSizes(SurfaceTexture::class.java) ?: return null
        if (sizes.isEmpty()) return null
        return sizes.filter { it.width <= 1280 && it.height <= 720 }
            .maxByOrNull { it.width.toLong() * it.height }
            ?: sizes.minByOrNull { it.width.toLong() * it.height }
    }

    fun close() {
        try { session?.stopRepeating() } catch (_: Exception) {}
        try { session?.close() } catch (_: Exception) {}
        session = null
        try { device?.close() } catch (_: Exception) {}
        device = null
        // The Surface is ours; the TEXTURE belongs to the program and is
        // released with it.
        try { surface?.release() } catch (_: Exception) {}
        surface = null
        thread?.quitSafely()
        thread = null
        handler = null
    }
}
