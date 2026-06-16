package app.archivewatch.android.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.widget.OverScroller
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * CapCut / iMovie-style clip timeline — the Android twin of the iOS
 * `ClipTimelineView` (CREATE-STUDIO-PLAN §5b, parity with iOS b45). The native
 * idioms the previous two-handle + separate-scrubber UI got wrong:
 *
 *  • The filmstrip SCROLLS under a FIXED center playhead — scrolling IS
 *    scrubbing, and the preview seeks to the frame under the playhead live.
 *  • PINCH to ZOOM the timeline (essential for long archive.org films),
 *    preserving the centered time.
 *  • The selection is a highlighted band with drag handles, but the primary
 *    way to set in/out is "Set Start / Set End at the playhead" (Compose
 *    buttons in the screen) — no alternating two-handle dance.
 *  • During playback the strip auto-scrolls so the playing frame stays under
 *    the playhead.
 *
 * Built as a self-contained custom `View` (not a HorizontalScrollView) so the
 * programmatic `follow()` during playback composes cleanly with pinch-zoom and
 * handle drags — the same reason the iOS version owns its scroll via a raw
 * UIScrollView. Both ends are centerable because the content is padded by half
 * the viewport width.
 */
@Composable
fun ClipTimeline(
    thumbnails: List<Bitmap?>,
    duration: Double,
    inSeconds: Double,
    outSeconds: Double,
    playhead: Double,
    isPlaying: Boolean,
    maxClip: Double,
    onScrub: (Double) -> Unit,
    onTrim: (newIn: Double, newOut: Double, previewAt: Double) -> Unit,
    modifier: Modifier = Modifier,
) {
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            ClipTimelineView(ctx).apply {
                this.onScrub = onScrub
                this.onTrim = onTrim
            }
        },
        update = { view ->
            view.onScrub = onScrub
            view.onTrim = onTrim
            view.maxClip = maxClip
            view.configure(duration, thumbnails)
            view.setSelection(inSeconds, outSeconds)
            if (isPlaying) view.follow(playhead)
        },
    )
}

internal class ClipTimelineView(context: Context) : View(context) {
    var onScrub: ((Double) -> Unit)? = null
    var onTrim: ((Double, Double, Double) -> Unit)? = null
    var maxClip: Double = 60.0

    private var duration: Double = 0.0
    private var thumbnails: List<Bitmap?> = emptyList()
    private var inSeconds: Double = 0.0
    private var outSeconds: Double = 0.0

    private var pps: Float = 0f                 // pixels per second (zoom)
    private var offsetX: Float = 0f             // scroll offset (content px scrolled left)
    private val stripTop get() = (height - stripHeightPx) / 2f
    private val stripHeightPx get() = height * 0.72f

    private var isProgrammatic = false
    private var draggingHandle = 0              // 0=none, -1=left, +1=right
    private var didInitialCenter = false

    private val accent = Color.rgb(255, 92, 53)  // brand marquee orange
    private val tilePaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val emptyTilePaint = Paint().apply { color = Color.rgb(28, 28, 28) }
    private val bandFill = Paint().apply { color = (accent and 0x00FFFFFF) or (46 shl 24) }
    private val bandStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = accent; style = Paint.Style.STROKE; strokeWidth = dp(3f)
    }
    private val handlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = accent }
    private val gripPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val playheadPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val playheadHaloPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(140, 0, 0, 0) }
    private val dimPaint = Paint().apply { color = Color.argb(140, 0, 0, 0) }

    private val scroller = OverScroller(context)
    private val handleW get() = dp(22f)

    // Pinch zoom anchored on the centered time.
    private var pinchStartPps = 0f
    private var pinchCenterTime = 0.0
    private val scaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
            scroller.forceFinished(true)
            pinchStartPps = pps
            pinchCenterTime = centerTime()
            return true
        }
        override fun onScale(detector: ScaleGestureDetector): Boolean {
            val minPps = width / max(1f, min(duration.toFloat(), 600f))  // up to 10 min across
            val maxPps = width / 1.5f                                    // down to ~1.5s across
            pps = (pinchStartPps * detector.scaleFactor).coerceIn(minPps, maxPps)
            setCenterTime(pinchCenterTime)
            invalidate()
            return true
        }
    })

    private val gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(e: MotionEvent): Boolean {
            scroller.forceFinished(true)
            return true
        }
        override fun onScroll(e1: MotionEvent?, e2: MotionEvent, dx: Float, dy: Float): Boolean {
            if (draggingHandle != 0) return false
            offsetX = (offsetX + dx).coerceIn(0f, contentWidth() - 0.0001f)
            emitScrub()
            invalidate()
            return true
        }
        override fun onFling(e1: MotionEvent?, e2: MotionEvent, vx: Float, vy: Float): Boolean {
            if (draggingHandle != 0) return false
            scroller.fling(offsetX.toInt(), 0, (-vx).toInt(), 0, 0, contentWidth().toInt(), 0, 0)
            postInvalidateOnAnimation()
            return true
        }
    })

    fun configure(duration: Double, thumbnails: List<Bitmap?>) {
        this.duration = max(duration, 0.001)
        this.thumbnails = thumbnails
        if (pps == 0f && width > 0) initZoom()
        invalidate()
    }

    fun setSelection(inSeconds: Double, outSeconds: Double) {
        if (draggingHandle != 0) return
        this.inSeconds = inSeconds
        this.outSeconds = outSeconds
        invalidate()
    }

    /** Auto-scroll so the playing frame stays under the center playhead. */
    fun follow(t: Double) {
        if (draggingHandle != 0) return
        setCenterTime(t)
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w > 0) {
            if (pps == 0f) initZoom()
            if (!didInitialCenter) { didInitialCenter = true; setCenterTime(inSeconds) }
        }
    }

    private fun initZoom() {
        // Default: show ~24s (or the whole film if shorter) across the width.
        pps = width / max(1f, min(duration.toFloat(), 24f))
    }

    private fun contentWidth(): Float = (duration * pps).toFloat()

    private fun centerTime(): Double = ((offsetX + width / 2f) / pps).toDouble().coerceIn(0.0, duration)

    private fun setCenterTime(t: Double) {
        isProgrammatic = true
        offsetX = (t.coerceIn(0.0, duration) * pps - width / 2f).toFloat()
            .coerceIn(0f, contentWidth().coerceAtLeast(0.0001f))
        isProgrammatic = false
    }

    private fun emitScrub() {
        if (isProgrammatic) return
        onScrub?.invoke(centerTime())
    }

    override fun computeScroll() {
        if (scroller.computeScrollOffset()) {
            offsetX = scroller.currX.toFloat().coerceIn(0f, contentWidth())
            emitScrub()
            postInvalidateOnAnimation()
        }
    }

    // x position on screen of a content time
    private fun screenX(t: Double): Float = (t * pps - offsetX).toFloat()

    @Suppress("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        // Handle drags take priority over scrubbing.
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val x = event.x
                val leftX = screenX(inSeconds)
                val rightX = screenX(outSeconds)
                draggingHandle = when {
                    abs(x - leftX) <= handleW -> -1
                    abs(x - rightX) <= handleW -> 1
                    else -> 0
                }
            }
            MotionEvent.ACTION_MOVE -> if (draggingHandle != 0) {
                val t = ((event.x + offsetX) / pps).toDouble().coerceIn(0.0, duration)
                if (draggingHandle == -1) {
                    var v = t.coerceIn(0.0, outSeconds - 0.5)
                    v = max(v, outSeconds - maxClip)
                    inSeconds = v
                    onTrim?.invoke(inSeconds, outSeconds, inSeconds)
                } else {
                    var v = t.coerceIn(inSeconds + 0.5, duration)
                    v = min(v, inSeconds + maxClip)
                    outSeconds = v
                    onTrim?.invoke(inSeconds, outSeconds, outSeconds)
                }
                invalidate()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> draggingHandle = 0
        }
        if (draggingHandle != 0) return true
        scaleDetector.onTouchEvent(event)
        if (!scaleDetector.isInProgress) gestureDetector.onTouchEvent(event)
        return true
    }

    override fun onDraw(canvas: Canvas) {
        if (width == 0 || pps == 0f) return
        val top = stripTop
        val bottom = top + stripHeightPx
        val cw = contentWidth()

        // Filmstrip tiles laid edge to edge across the content, scrolled by offsetX.
        val n = thumbnails.size.coerceAtLeast(1)
        val tileW = cw / n
        for (i in 0 until n) {
            val left = i * tileW - offsetX
            val right = left + tileW + 1
            if (right < 0 || left > width) continue
            val dst = RectF(left, top, right, bottom)
            val bmp = thumbnails.getOrNull(i)
            if (bmp != null) {
                val src = Rect(0, 0, bmp.width, bmp.height)
                canvas.drawBitmap(bmp, src, dst, tilePaint)
            } else {
                canvas.drawRect(dst, emptyTilePaint)
            }
        }

        // Dim outside the selection band.
        val inX = screenX(inSeconds)
        val outX = screenX(outSeconds)
        if (inX > 0) canvas.drawRect(0f, top, inX, bottom, dimPaint)
        if (outX < width) canvas.drawRect(outX, top, width.toFloat(), bottom, dimPaint)

        // Selection band.
        canvas.drawRect(inX, top, outX, bottom, bandFill)
        val r = dp(6f)
        canvas.drawRoundRect(RectF(inX, top - dp(2f), outX, bottom + dp(2f)), r, r, bandStroke)

        // Handles + grips.
        drawHandle(canvas, inX, top, bottom)
        drawHandle(canvas, outX, top, bottom)

        // Fixed center playhead (subtle dark halo for contrast over bright frames).
        val cx = width / 2f
        canvas.drawRoundRect(
            RectF(cx - dp(2.5f), dp(2f), cx + dp(2.5f), height - dp(2f)),
            dp(2.5f), dp(2.5f), playheadHaloPaint,
        )
        canvas.drawRoundRect(
            RectF(cx - dp(1.5f), dp(2f), cx + dp(1.5f), height - dp(2f)),
            dp(1.5f), dp(1.5f), playheadPaint,
        )
    }

    private fun drawHandle(canvas: Canvas, x: Float, top: Float, bottom: Float) {
        val hw = handleW
        val r = dp(5f)
        canvas.drawRoundRect(
            RectF(x - hw / 2, top - dp(4f), x + hw / 2, bottom + dp(4f)), r, r, handlePaint,
        )
        canvas.drawRoundRect(
            RectF(x - dp(1f), (top + bottom) / 2 - dp(11f), x + dp(1f), (top + bottom) / 2 + dp(11f)),
            dp(1f), dp(1f), gripPaint,
        )
    }

    private fun dp(v: Float): Float = v * resources.displayMetrics.density
}
