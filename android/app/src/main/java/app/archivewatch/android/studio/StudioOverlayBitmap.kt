package app.archivewatch.android.studio

// The lower third, drawn once into a Bitmap and uploaded as a texture
// (docs/WATCH-TOGETHER.md §4). The Android counterpart of the Apple side's
// cached overlay, and cached for the same measured reason: rasterising text
// every frame took the iOS composite from 3.40 ms to 9.02 ms (§9).
//
// It carries the film's title, year and director, and — when the rights audit
// cleared it by age — the PROVENANCE line. That line is not decoration: it is
// the learning-orientation answer (§2), the same sentence every platform
// shows, and the reason a viewer can tell why this film is free to watch.

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface

object StudioOverlayBitmap {

    /** Marquee orange — the one brand colour, shared with every platform. */
    private const val MARQUEE = "#FF5C35"

    /**
     * The lower third PLUS the chat column, in one bitmap.
     *
     * One bitmap because the Android overlay is a single texture
     * (`StudioProgramGl.setOverlayBitmap`), unlike Apple's two cached layers —
     * so a new chat line means re-rendering both and re-uploading. That is
     * cheap at once a second and only when the line ids change; it would not
     * be cheap per frame, which is the measured reason the overlay is cached
     * at all (§9).
     *
     * The pill alphas are Apple's numbers on purpose: 0.88, and 0.92 for an
     * event. At 0.68 the type was mud over a silent film's bright intertitles
     * (§6.4a), and two platforms drawing the same overlay differently is a
     * parity bug waiting to be found on the glass.
     */
    fun withChat(width: Int, height: Int,
                 title: String, subtitle: String, provenance: String?,
                 chat: List<ChatLine>): Bitmap {
        val bmp = lowerThird(width, height, title, subtitle, provenance)
        if (chat.isEmpty()) return bmp
        val c = Canvas(bmp)
        val unit = height / 40f
        val left = unit * 3f
        val colWidth = width * 0.34f
        val pad = unit * 0.55f
        val gap = unit * 0.35f
        val textSize = unit * 0.95f

        val authorPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.textSize = textSize
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        }
        val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.textSize = textSize
            color = Color.WHITE
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
        }

        // Bottom-up: the NEWEST message must always be visible, so the oldest
        // is what falls off the top. A top-down layout with a height clamp
        // drops the newest, which is the one line that matters.
        val bottom = lowerThirdTop(height, !provenance.isNullOrEmpty()) - unit * 0.6f
        var y = bottom
        val lineH = textSize * 1.35f
        for (line in chat.asReversed()) {
            authorPaint.color = if (line.isEvent) Color.parseColor(MARQUEE)
                                else Color.rgb(115, 158, 255)
            val authorText = line.author + "  "
            val authorW = authorPaint.measureText(authorText)
            val wrapped = wrap(line.text, bodyPaint, colWidth - pad * 2 - authorW, authorW)
            val blockH = wrapped.size * lineH + pad * 1.4f
            if (y - blockH < unit * 4f) break

            var widest = 0f
            wrapped.forEachIndexed { i, seg ->
                val w = bodyPaint.measureText(seg) + (if (i == 0) authorW else 0f)
                if (w > widest) widest = w
            }
            val pillW = minOf(colWidth, widest + pad * 2)
            val top = y - blockH
            c.drawRoundRect(left, top, left + pillW, y, unit * 0.4f, unit * 0.4f,
                Paint().apply {
                    color = Color.argb(if (line.isEvent) 235 else 224, 0, 0, 0)
                })

            var ty = top + pad * 0.7f + textSize
            wrapped.forEachIndexed { i, seg ->
                val x = left + pad + (if (i == 0) authorW else 0f)
                c.drawText(seg, x, ty, bodyPaint)
                if (i == 0) c.drawText(authorText, left + pad, ty, authorPaint)
                ty += lineH
            }
            y = top - gap
        }
        return bmp
    }

    /** Greedy word wrap. The first line is indented past the author name. */
    private fun wrap(text: String, paint: Paint, maxWidth: Float, firstIndent: Float): List<String> {
        if (maxWidth <= 0f) return listOf(text)
        val out = ArrayList<String>()
        var current = StringBuilder()
        var budget = maxWidth
        for (word in text.split(' ')) {
            val candidate = if (current.isEmpty()) word else current.toString() + " " + word
            if (paint.measureText(candidate) <= budget || current.isEmpty()) {
                current = StringBuilder(candidate)
            } else {
                out.add(current.toString())
                current = StringBuilder(word)
                budget = maxWidth + firstIndent   // later lines start at the margin
            }
        }
        if (current.isNotEmpty()) out.add(current.toString())
        return out
    }

    /**
     * The y of the lower third's scrim top.
     *
     * Both drawers read it from HERE. The chat column used to carry its own
     * guess at where the lower third began (`height - unit * 9`), and on the
     * Google TV at 720p that put its two newest pills on top of the film's
     * title — the title is the one thing the lower third exists to say. Two
     * numbers describing one edge will drift; this is the edge.
     */
    private fun lowerThirdTop(height: Int, hasProvenance: Boolean): Float {
        val unit = height / 40f
        val baseY = height - unit * 4f
        val lines = 2 + (if (hasProvenance) 1 else 0)
        return baseY - unit * 2.6f * lines - unit * 2f
    }

    fun lowerThird(width: Int, height: Int,
                   title: String, subtitle: String, provenance: String?): Bitmap {
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)

        // Everything is sized from the frame height, so 720p and 1080p give
        // the same picture rather than the same pixel counts.
        val unit = height / 40f
        val left = unit * 3f
        val baseY = height - unit * 4f

        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = unit * 2.6f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val subtitlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(235, 255, 255, 255)
            textSize = unit * 1.6f
        }
        val provenancePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor(MARQUEE)
            textSize = unit * 1.25f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }

        val lines = 2 + (if (provenance.isNullOrEmpty()) 0 else 1)
        val blockTop = baseY - unit * 2.6f * lines - unit
        // A scrim only under the text, not the full width: a full-width band
        // dims the camera tile, which is a defect the Apple side shipped and
        // then fixed by looking at it (§9).
        val scrimRight = left + maxOf(titlePaint.measureText(title),
                                      subtitlePaint.measureText(subtitle),
                                      provenance?.let { provenancePaint.measureText(it) } ?: 0f) + unit * 3f
        val scrim = Paint().apply { color = Color.argb(150, 0, 0, 0) }
        c.drawRect(0f, lowerThirdTop(height, !provenance.isNullOrEmpty()), scrimRight, height.toFloat(), scrim)

        // The marquee rule, left of the text — the same device the Apple
        // lower third uses.
        c.drawRect(left - unit, blockTop - unit * 0.2f, left - unit * 0.7f, baseY + unit * 0.4f,
                   Paint().apply { color = Color.parseColor(MARQUEE) })

        var y = blockTop + unit * 1.6f
        c.drawText(title, left, y, titlePaint)
        y += unit * 2.2f
        c.drawText(subtitle, left, y, subtitlePaint)
        if (!provenance.isNullOrEmpty()) {
            y += unit * 1.9f
            c.drawText(provenance.uppercase(), left, y, provenancePaint)
        }
        return bmp
    }
}
