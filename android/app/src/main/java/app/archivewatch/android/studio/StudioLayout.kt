package app.archivewatch.android.studio


/**
 * Where the film and the camera sit in the program frame.
 *
 * A PORT of the Swift `StudioLayout.rects(in:cameraAspect:)`, number for
 * number, because the two must agree: a host who picks "Side by side" on a
 * phone and on a Mac is picking the same picture, and two implementations of
 * one geometry is how they stop being the same picture
 * (`cross-platform-parity-discipline`).
 *
 * Android had `layoutShowsCamera`, a boolean, and a hardcoded corner tile — so
 * two of the five existed here and the other three were offered nowhere. Owner,
 * 2026-09-20: *"You should close gaps that can be closed on any platform. The
 * goal is parity, where it makes sense."*
 *
 * Rects are in PIXELS with the origin at the BOTTOM-LEFT, matching the Swift
 * side's Core Image space, so the numbers can be compared directly rather than
 * mentally flipped. `StudioProgramGl` converts to NDC.
 *
 * `LayoutRect` is a plain data class rather than `android.graphics.RectF`
 * ON PURPOSE: RectF is a STUB on the JVM, so a unit test of this geometry
 * throws "Method width in android.graphics.RectF not mocked" and every
 * assertion reads 0.0. Geometry that both platforms must agree on has to be
 * testable without a device, or the agreement is never checked.
 */
data class LayoutRect(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top
}

/**
 * Where the film and the camera sit in the program frame — see LayoutRect
 * above for why the rects are plain data.
 */
enum class StudioLayout(val label: String) {
    FILM("Film only"),
    CORNER("Film with you in the corner"),
    THEATRE("Theatre row (you along the bottom)"),
    SIDE("Side by side"),
    HOST("You, with the film inset");

    val showsCamera: Boolean get() = this != FILM

    /** True when the CAMERA is the ground and the film sits on top of it. */
    val cameraIsBackground: Boolean get() = this == HOST

    data class Rects(val film: LayoutRect, val camera: LayoutRect?)

    fun rects(width: Float, height: Float, cameraAspect: Float): Rects {
        val full = LayoutRect(0f, 0f, width, height)
        return when (this) {
            FILM -> Rects(full, null)
            CORNER -> {
                val w = width * 0.26f
                val h = w / maxOf(cameraAspect, 0.1f)
                val inset = width * 0.05f
                Rects(full, LayoutRect(width - w - inset, inset, width - inset, inset + h))
            }
            THEATRE -> {
                // 0.38, not 0.26: at 0.26 this was CORNER moved 64 px down —
                // the same tile in the same corner — and the setting did
                // nothing a host could see (found 2026-09-20). Position cannot
                // distinguish them, because a centred strip lands on the lower
                // third, so size does.
                val h = height * 0.38f
                val w = h * cameraAspect
                val inset = width * 0.05f
                Rects(full, LayoutRect(width - w - inset, 0f, width - inset, h))
            }
            SIDE -> {
                val fw = (width * 2f / 3f)
                val filmH = fw * 9f / 16f
                val film = LayoutRect(0f, (height - filmH) / 2f, fw, (height + filmH) / 2f)
                val cw = width - fw
                val ch = cw / maxOf(cameraAspect, 0.1f)
                Rects(film, LayoutRect(fw, (height - ch) / 2f, fw + cw, (height + ch) / 2f))
            }
            HOST -> {
                val w = width * 0.26f
                val h = w * 9f / 16f
                val inset = width * 0.05f
                Rects(LayoutRect(width - w - inset, height - h - inset, width - inset, height - inset),
                      full)
            }
        }
    }

    companion object {
        fun from(raw: String?): StudioLayout =
            entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: CORNER
    }
}
