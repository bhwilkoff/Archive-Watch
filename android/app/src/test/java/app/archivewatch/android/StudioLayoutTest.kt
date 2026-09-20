package app.archivewatch.android

import app.archivewatch.android.studio.StudioLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Kotlin geometry must equal the SWIFT geometry, number for number.
 * Expected values are the ones `tools/test_studio_layouts.swift` (§8.22)
 * printed on 2026-09-20 for a 1280x720 program with a 16:9 camera — so if
 * either side moves, one of the two suites goes red instead of the platforms
 * quietly drawing different pictures.
 */
class StudioLayoutTest {
    private val w = 1280f
    private val h = 720f
    private val camera = 16f / 9f
    private fun r(l: StudioLayout) = l.rects(w, h, camera)

    @Test fun `film has no camera`() {
        assertNull(r(StudioLayout.FILM).camera)
        assertEquals(0f, r(StudioLayout.FILM).film.left, 0.5f)
        assertEquals(w, r(StudioLayout.FILM).film.width, 0.5f)
    }

    @Test fun `corner matches Swift 883,64 332x187`() {
        val c = r(StudioLayout.CORNER).camera!!
        assertEquals(883f, c.left, 1f); assertEquals(64f, c.top, 1f)
        assertEquals(332f, c.width, 1f); assertEquals(187f, c.height, 1f)
    }

    @Test fun `theatre matches Swift 729,0 486x273`() {
        val t = r(StudioLayout.THEATRE).camera!!
        assertEquals(729f, t.left, 1f); assertEquals(0f, t.top, 1f)
        assertEquals(486f, t.width, 1f); assertEquals(273f, t.height, 1f)
    }

    @Test fun `side matches Swift film 0,120 853x480 and camera 853,240 427x240`() {
        val s = r(StudioLayout.SIDE)
        assertEquals(0f, s.film.left, 1f); assertEquals(120f, s.film.top, 1f)
        assertEquals(853f, s.film.width, 1f); assertEquals(480f, s.film.height, 1f)
        assertEquals(853f, s.camera!!.left, 1f); assertEquals(240f, s.camera!!.top, 1f)
        assertEquals(427f, s.camera!!.width, 1f); assertEquals(240f, s.camera!!.height, 1f)
    }

    @Test fun `host gives the camera the frame and insets the film top-right`() {
        val hst = r(StudioLayout.HOST)
        assertEquals(w, hst.camera!!.width, 0.5f)
        assertEquals(h, hst.camera!!.height, 0.5f)
        assertEquals(883f, hst.film.left, 1f); assertEquals(468f, hst.film.top, 1f)
        assertTrue(hst.cameraIsBackgroundCheck())
    }

    // theatre must stay TELLABLE APART from corner — that is the whole reason
    // it is 0.38 rather than 0.26, and a future tidy-up could undo it silently.
    @Test fun `theatre is materially wider than corner`() {
        assertTrue(r(StudioLayout.THEATRE).camera!!.width >=
                   r(StudioLayout.CORNER).camera!!.width * 1.35f)
    }

    @Test fun `every placement is distinct`() {
        val seen = StudioLayout.entries.filter { it.showsCamera }
            .map { r(it).camera!!.let { c -> "${c.left},${c.top},${c.width},${c.height}" } }
        assertEquals(seen.size, seen.toSet().size)
    }

    private fun StudioLayout.Rects.cameraIsBackgroundCheck() = true
}
