package app.archivewatch.android

import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.archivewatch.android.studio.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicReference

/**
 * The whole PROGRAM on Android: film + a corner tile + the lower third, all
 * composited by one GLES pass into MediaCodec (docs/WATCH-TOGETHER.md §6.2c).
 *
 * THE CORNER TILE'S SOURCE IS A SECOND FILM, not a camera, and that is a
 * deliberate substitution rather than a shortcut: neither television on this
 * bench has a camera, and from the renderer's side CameraX, Camera2 and a
 * second ExoPlayer are the same thing — a producer rendering into a
 * SurfaceTexture. What is under test here is the COMPOSITE: two external
 * textures, z-order, the tile's rect, and a blended overlay above both.
 * Swapping the real camera in is a change of source, not of pipeline, and the
 * camera's own cost is measured on a phone (§9).
 */
@RunWith(AndroidJUnit4::class)
class StudioProgramDeviceTest {

    private val args = InstrumentationRegistry.getArguments()
    private val host: String = args.getString("rtmpHost") ?: "10.0.0.90"
    private val port = 19351
    private val filmUrl = args.getString("filmUrl")
        ?: "https://dn600307.us.archive.org/0/items/PreviewTheKissOfDeath/preview%20-%20The%20Kiss%20of%20Death.mp4"
    private val tileUrl = args.getString("tileUrl")
        ?: "https://dn600304.us.archive.org/0/items/silent-arrive-de-cyclistes-turin/Arriv%C3%A9e%20de%20cyclistes%20%C3%A0%20Turin.mp4"

    private fun serverIsUp(): Boolean = try {
        Socket().use { it.connect(InetSocketAddress(host, port), 1500); true }
    } catch (_: Exception) { false }

    @Test fun publishesTheWholeProgram() {
        assumeTrue("no RTMP server at $host:$port — skipping", serverIsUp())

        val w = 1280; val h = 720; val fps = 30
        val enc = StudioVideoEncoder(w, h, fps, 4_000_000)
        enc.start()
        val gl = StudioGl(enc.inputSurface); gl.setUp()
        val pg = StudioProgramGl(w, h); pg.setUp()

        // The lower third, rasterised ONCE.
        pg.setOverlayBitmap(StudioOverlayBitmap.lowerThird(
            w, h,
            title = "The Kiss of Death",
            subtitle = "1916 · Victor Sjöström",
            provenance = "Public domain — published 1916, before 1930"))

        val instr = InstrumentationRegistry.getInstrumentation()
        // THE FILM'S ASPECT COMES FROM THE PLAYER, not from a constant. A
        // hardcoded 4:3 pillarboxes a 16:9 film as though it were square-ish,
        // which is the defect §6.2c left open.
        val filmAspect = AtomicReference(16f / 9f)
        var film: ExoPlayer? = null
        var tile: ExoPlayer? = null
        instr.runOnMainSync {
            film = ExoPlayer.Builder(instr.targetContext).build().apply {
                addListener(object : Player.Listener {
                    override fun onVideoSizeChanged(size: VideoSize) {
                        if (size.width > 0 && size.height > 0) {
                            filmAspect.set(size.width.toFloat() / size.height *
                                           (if (size.pixelWidthHeightRatio > 0) size.pixelWidthHeightRatio else 1f))
                        }
                    }
                })
                setVideoSurface(Surface(pg.filmSurfaceTexture))
                setMediaItem(MediaItem.fromUri(filmUrl)); prepare(); playWhenReady = true
            }
            tile = ExoPlayer.Builder(instr.targetContext).build().apply {
                setVideoSurface(Surface(pg.cameraSurfaceTexture))
                setMediaItem(MediaItem.fromUri(tileUrl)); prepare()
                repeatMode = Player.REPEAT_MODE_ALL; playWhenReady = true
            }
        }

        var n = 0
        while (n < 600 && (pg.framesAvailable.get() < 5 || pg.cameraFramesAvailable.get() < 3)) {
            drawProgram(gl, pg, filmAspect.get(), n, fps); enc.drain { _, _, _ -> }; n++
            Thread.sleep(30)
        }
        assertTrue("film frames=${pg.framesAvailable.get()} tile frames=${pg.cameraFramesAvailable.get()}",
                   pg.framesAvailable.get() >= 5 && pg.cameraFramesAvailable.get() >= 3)

        var guard = 0
        while (enc.avcC == null && guard < 60) {
            drawProgram(gl, pg, filmAspect.get(), n + guard, fps); enc.drain { _, _, _ -> }; guard++
        }
        assertNotNull("no avcC", enc.avcC)

        val p = RtmpPublisher()
        p.publish("rtmp://$host:$port/live", "androidprogram",
            RtmpStreamConfig(w, h, fps.toDouble(), 4_000_000, enc.avcC!!,
                             44100, 1, 128_000, RealAac.asc),
            declareAudio = false)
            // Begin on a KEYFRAME: until one arrives a joining viewer and a
            // recording server have nothing decodable (see requestKeyframe).
            enc.requestKeyframe()

        var frame = n + 100
        val deadline = System.currentTimeMillis() + 25_000
        while (System.currentTimeMillis() < deadline) {
            drawProgram(gl, pg, filmAspect.get(), frame, fps)
            enc.drain { a, k, t -> p.sendVideo(a, k, t, t) }
            frame++; Thread.sleep(25)
        }
        enc.drain { a, k, t -> p.sendVideo(a, k, t, t) }

        val report = "encoded=${p.health.videoFramesSent} film=${pg.framesAvailable.get()} " +
                     "tile=${pg.cameraFramesAvailable.get()} aspect=${filmAspect.get()} state=${p.health.state}"
        assertTrue("almost nothing was encoded — $report", p.health.videoFramesSent > 20)
        assertEquals("the connection did not survive — $report", "publishing", p.health.state)
        Thread.sleep(1500)
        p.close()
        instr.runOnMainSync { film?.release(); tile?.release() }
        pg.tearDown(); gl.tearDown(); enc.stop()
    }

    /** One composed frame: film, then the tile above it, then the overlay. */
    private fun drawProgram(gl: StudioGl, pg: StudioProgramGl, aspect: Float, n: Int, fps: Int) {
        gl.makeCurrent()
        pg.updateFilmFrame(); pg.updateCameraFrame()
        gl.clear(0f, 0f, 0f)
        pg.drawFilm(aspect)
        pg.drawCameraCorner(4f / 3f)
        pg.drawOverlay()
        gl.swap(n.toLong() * 1_000_000_000L / fps)
    }
}
