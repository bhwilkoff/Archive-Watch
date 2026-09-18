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
        c.drawRect(0f, blockTop - unit, scrimRight, height.toFloat(), scrim)

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
