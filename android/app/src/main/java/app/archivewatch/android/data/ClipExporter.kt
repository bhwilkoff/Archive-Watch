package app.archivewatch.android.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.text.TextPaint
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.Contrast
import androidx.media3.effect.HslAdjustment
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbAdjustment
import androidx.media3.effect.RgbFilter
import androidx.media3.effect.SpeedChangeEffect
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextureOverlay
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import java.io.File
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Clip Studio export engine — the Android twin of the iOS `ClipExporter`
 * (CREATE-STUDIO-PLAN §5, Decision 033). Native frameworks only (Decision
 * 028): Jetpack Media3 `Transformer` for the trim/reframe/overlay/encode
 * pipeline; `MediaStore` to save (handled in the screen).
 *
 * STREAM, DON'T DOWNLOAD (CREATE-STUDIO-PLAN §3, parity with iOS b44).
 * Archive.org films can be hours long and many gigabytes, so we NEVER
 * download the whole file. Media3 `Transformer` reads the REMOTE URI
 * directly through an `OkHttpDataSource` (the same byte-range, redirect-
 * resilient path the player uses), so only the ranges the ≤60s clip needs
 * (moov + the clip's samples) are read. Thumbnails come from a ranged
 * `MediaMetadataRetriever.setDataSource(url, headers)`. The whole-file
 * download path is gone.
 *
 * GIF: Android has NO native GIF encoder, so MP4 only — the GIF gap is
 * documented in PARITY / ANDROID-DESIGN (WebP / a vendored encoder is a
 * later option; we do NOT add a third-party GIF lib).
 */
enum class ClipAspect(val label: String) {
    ORIGINAL("Original"),
    VERTICAL("9:16"),
    SQUARE("1:1"),
    WIDE("16:9");

    /** Preview aspect ratio (width / height); null = use the source's. */
    val ratio: Float?
        get() = when (this) {
            ORIGINAL -> null
            VERTICAL -> 9f / 16f
            SQUARE -> 1f
            WIDE -> 16f / 9f
        }

    /** Render canvas for a 1080-class export. ORIGINAL keeps the source size. */
    fun renderSize(srcW: Int, srcH: Int): Size = when (this) {
        ORIGINAL -> Size(srcW, srcH)
        VERTICAL -> Size(1080, 1920)
        SQUARE -> Size(1080, 1080)
        WIDE -> Size(1920, 1080)
    }

    companion object {
        fun from(raw: String): ClipAspect =
            entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: VERTICAL
    }
}

/** v1 Android format set — MP4 only (GIF deferred; see class doc). */
enum class ClipFormat(val label: String, val maxDuration: Double, val fileExtension: String) {
    VIDEO("Video", 60.0, "mp4");

    companion object {
        fun from(raw: String): ClipFormat = VIDEO
    }
}

/**
 * Color-grade "looks" — era-appropriate film treatments for repertory PD
 * cinema (CREATE-STUDIO-PLAN §4, Decision 033 v2). The Android twin of the iOS
 * `ClipLook`; the SAME six look names, mapped to native `androidx.media3.effect`
 * effects (no third-party). `NONE` is a no-op fast path.
 *
 * iOS uses CIFilter chains; Media3 has no equivalent named film presets, so each
 * look maps to the closest native RGB/HSL/grayscale effect:
 *  - SILENT      → sepia warm tone via `RgbAdjustment` (boost red, cut blue)
 *                  (≈ iOS CISepiaTone).
 *  - NOIR        → grayscale (`RgbFilter.createGrayscaleFilter()`) + a contrast
 *                  lift for the high-key noir punch (≈ iOS CIPhotoEffectNoir).
 *  - FADED       → reduced contrast + desaturation (`Contrast` < 0 +
 *                  `HslAdjustment` saturation down) (≈ iOS CIPhotoEffectFade).
 *                  No vignette: Media3 1.9.4 has no native vignette effect.
 *  - TECHNICOLOR → boosted saturation (`HslAdjustment` saturation up) + slight
 *                  contrast (≈ iOS CIPhotoEffectChrome + saturation 1.25).
 *  - MONO (B&W)  → grayscale (`RgbFilter.createGrayscaleFilter()`)
 *                  (≈ iOS CIPhotoEffectMono).
 */
enum class ClipLook(val label: String) {
    NONE("None"),
    SILENT("Silent"),
    NOIR("Noir"),
    FADED("Faded"),
    TECHNICOLOR("Techni"),
    MONO("B&W");

    /** Native Media3 video effects for this look. Empty for NONE. */
    @OptIn(UnstableApi::class)
    fun videoEffects(): List<Effect> = when (this) {
        NONE -> emptyList()
        // Warm sepia: lift red, hold green, cut blue. Approximates CISepiaTone.
        SILENT -> listOf(
            RgbAdjustment.Builder()
                .setRedScale(1.25f)
                .setGreenScale(1.02f)
                .setBlueScale(0.72f)
                .build(),
        )
        // Grayscale + contrast lift for the high-contrast noir look.
        NOIR -> listOf(
            RgbFilter.createGrayscaleFilter(),
            Contrast(0.30f),
        )
        // Washed/faded: drop contrast, desaturate. (No native vignette in 1.9.4.)
        FADED -> listOf(
            Contrast(-0.20f),
            HslAdjustment.Builder().adjustSaturation(-40f).build(),
        )
        // Punchy color: saturation up + a touch of contrast.
        TECHNICOLOR -> listOf(
            HslAdjustment.Builder().adjustSaturation(35f).build(),
            Contrast(0.12f),
        )
        // Straight grayscale.
        MONO -> listOf(RgbFilter.createGrayscaleFilter())
    }

    companion object {
        fun from(raw: String): ClipLook =
            entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: NONE
    }
}

/** Playback speed for the export — mirrors iOS 0.5× / 1× / 2×. */
enum class ClipSpeed(val multiplier: Float, val label: String) {
    HALF(0.5f, "0.5×"),
    ONE(1f, "1×"),
    TWO(2f, "2×");

    companion object {
        fun from(raw: String): ClipSpeed =
            entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: ONE
    }
}

// MARK: Caption style (font / size / color / background / position)

/**
 * Caption typeface family — the Android twin of iOS `CaptionFont`. Same four
 * choices, mapped to native `Typeface` families.
 *  - SANS  → DEFAULT (system sans, bold)    (≈ iOS .system)
 *  - ROUND → sans-serif (no rounded family in stock Android; SANS_SERIF bold,
 *            the nearest native equivalent — documented divergence)
 *  - SERIF → Typeface.SERIF                   (≈ iOS .serif)
 *  - MONO  → Typeface.MONOSPACE               (≈ iOS .mono)
 */
enum class CaptionFont(val label: String) {
    SANS("Sans"),
    ROUND("Round"),
    SERIF("Serif"),
    MONO("Mono");

    fun typeface(): Typeface = when (this) {
        SANS -> Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        ROUND -> Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        SERIF -> Typeface.create(Typeface.SERIF, Typeface.BOLD)
        MONO -> Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
    }

    companion object {
        fun from(raw: String): CaptionFont =
            entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: SANS
    }
}

/** Caption fill color — white / yellow / black (mirrors iOS `CaptionColor`). */
enum class CaptionColor(val label: String, val argb: Int) {
    WHITE("White", Color.WHITE),
    YELLOW("Yellow", Color.argb(255, 255, 214, 10)),
    BLACK("Black", Color.BLACK);

    companion object {
        fun from(raw: String): CaptionColor =
            entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: WHITE
    }
}

/** Caption backing — drop shadow / solid box / plain (mirrors iOS). */
enum class CaptionBackground(val label: String) {
    SHADOW("Shadow"),
    BOX("Box"),
    PLAIN("Plain");

    companion object {
        fun from(raw: String): CaptionBackground =
            entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: SHADOW
    }
}

/** Caption size step — S / M / L (scale factor on the base size). */
enum class CaptionSize(val label: String, val scale: Float) {
    SMALL("S", 0.8f),
    MEDIUM("M", 1.0f),
    LARGE("L", 1.3f);

    companion object {
        fun from(raw: String): CaptionSize =
            entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: MEDIUM
    }
}

/**
 * Caption look + placement, shared by the live preview (Compose) and the
 * burn-in (Canvas) so the editor is WYSIWYG (CREATE-STUDIO-PLAN §3, parity
 * with iOS b46). `posX`/`posY` are the NORMALIZED center of the caption in
 * the render canvas (0,0 = top-left, 1,1 = bottom-right) — the caption can be
 * dragged onto the video OR into the letterbox bars.
 */
data class CaptionStyle(
    val posX: Float = 0.5f,
    val posY: Float = 0.82f,
    val font: CaptionFont = CaptionFont.SANS,
    val size: CaptionSize = CaptionSize.MEDIUM,
    val color: CaptionColor = CaptionColor.WHITE,
    val background: CaptionBackground = CaptionBackground.SHADOW,
)

data class ClipSpec(
    /** Remote archive.org URL — the engine streams it; nothing is downloaded. */
    val sourceURL: String,
    val archiveID: String,
    val title: String,
    val sourceDetailsURL: String,
    val creditLine: String,
    val inSeconds: Double,
    val durationSeconds: Double,
    val aspect: ClipAspect,
    val caption: String,
    val format: ClipFormat,
    val look: ClipLook = ClipLook.NONE,
    val speed: ClipSpeed = ClipSpeed.ONE,
    val captionStyle: CaptionStyle = CaptionStyle(),
)

sealed class ClipExportException(message: String) : Exception(message) {
    object NoVideoTrack : ClipExportException("This title has no video track to clip.")
    object ExportFailed : ClipExportException("The clip couldn't be rendered.")
    data class Failed(val reason: String) : ClipExportException(reason)
}

@OptIn(UnstableApi::class)
class ClipExporter(
    private val context: Context,
    private val okHttp: OkHttpClient,
) {
    // One export at a time (single hardware encoder).
    private val exportMutex = Mutex()

    private val clipsDir: File
        get() = File(context.cacheDir, "clips").apply { mkdirs() }

    fun renderFile(filename: String): File = File(clipsDir, filename)

    // MARK: Source inspection (ranged — no download)

    /**
     * Read the oriented (rotation-applied) video size + duration directly off
     * the REMOTE stream via a ranged `MediaMetadataRetriever`. Only the moov
     * atom is fetched, not the whole file.
     */
    suspend fun probeSource(remoteURL: String): SourceInfo? = withContext(Dispatchers.IO) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(remoteURL, retrieverHeaders())
            val w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            val h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            val rot = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val durMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            if (w == null || h == null) return@withContext null
            val (ow, oh) = if (rot == 90 || rot == 270) Pair(h, w) else Pair(w, h)
            SourceInfo(width = ow, height = oh, durationSeconds = durMs / 1000.0)
        } catch (_: Exception) {
            null
        } finally {
            runCatching { retriever.release() }
        }
    }

    /**
     * Grab `count` filmstrip thumbnails across the duration directly off the
     * remote stream (ranged). Emits each frame as it decodes via `onFrame` so
     * the timeline fills in progressively (the iOS `generateThumbnails` shape).
     */
    suspend fun streamThumbnails(
        remoteURL: String,
        durationSeconds: Double,
        count: Int,
        onFrame: (index: Int, bitmap: Bitmap) -> Unit,
    ) = withContext(Dispatchers.IO) {
        if (durationSeconds <= 0) return@withContext
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(remoteURL, retrieverHeaders())
            for (i in 0 until count) {
                val tUs = (durationSeconds * (i + 0.5) / count * 1_000_000).toLong()
                val frame = retriever.getFrameAtTime(tUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                if (frame != null) {
                    val scaled = Bitmap.createScaledBitmap(
                        frame,
                        160,
                        (160 * frame.height / frame.width).coerceAtLeast(1),
                        true,
                    )
                    withContext(Dispatchers.Main) { onFrame(i, scaled) }
                }
            }
        } catch (_: Exception) {
            // Partial filmstrips are acceptable — the editor stays usable.
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun retrieverHeaders(): Map<String, String> =
        mapOf("User-Agent" to "ArchiveWatch-Android/1.0")

    // MARK: Video export (trim + reframe + caption + credit) — off the stream

    suspend fun exportVideo(
        spec: ClipSpec,
        onProgress: (Double) -> Unit,
    ): File = exportMutex.withLock {
        val info = probeSource(spec.sourceURL) ?: throw ClipExportException.NoVideoTrack
        val renderSize = spec.aspect.renderSize(info.width, info.height)

        val out = File(clipsDir, "ArchiveWatch-${UUID.randomUUID().toString().take(8)}.mp4")
        if (out.exists()) out.delete()

        // Trim window. Media3 ClippingConfiguration uses millis on the source
        // timeline; the engine reads only these sample ranges over HTTP.
        val startMs = (spec.inSeconds * 1000).toLong()
        val endMs = ((spec.inSeconds + spec.durationSeconds) * 1000).toLong()

        val mediaItem = MediaItem.Builder()
            .setUri(Uri.parse(spec.sourceURL))
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .build(),
            )
            .build()

        val effects = mutableListOf<Effect>()
        // Color grade FIRST, on the raw frames, before reframe/overlay (so the
        // burned-in caption + credit stay un-graded, matching the iOS two-pass
        // intent where the grade only touches the source clip).
        effects.addAll(spec.look.videoEffects())
        // Speed (video): a GL speed effect re-times the frames. The matching
        // audio speed is applied as an AudioProcessor below so A/V stay in sync.
        if (spec.speed != ClipSpeed.ONE) {
            effects.add(SpeedChangeEffect(spec.speed.multiplier))
        }
        // Reframe to the chosen canvas (letterbox/pillarbox into the matte).
        if (spec.aspect != ClipAspect.ORIGINAL) {
            effects.add(
                Presentation.createForWidthAndHeight(
                    renderSize.width, renderSize.height, Presentation.LAYOUT_SCALE_TO_FIT,
                ),
            )
        }
        // Always-on provenance credit + optional styled caption, burned in as a
        // single canvas-sized bitmap overlay (caption placed at its normalized
        // position so the burn-in matches the live preview).
        effects.add(makeOverlayEffect(renderSize, spec.caption, spec.creditLine, spec.captionStyle))

        // Audio speed (Sonic) keeps the soundtrack in step with the video
        // SpeedChangeEffect. Empty list = no audio processing for 1× speed.
        val audioProcessors: List<AudioProcessor> =
            if (spec.speed != ClipSpeed.ONE) {
                listOf(SonicAudioProcessor().apply { setSpeed(spec.speed.multiplier) })
            } else {
                emptyList()
            }

        val edited = EditedMediaItem.Builder(mediaItem)
            .setEffects(Effects(ImmutableList.copyOf(audioProcessors), ImmutableList.copyOf(effects)))
            .build()

        // The remote source is read through an OkHttpDataSource (ranged GETs,
        // the player's resilient path), wired into the Transformer via an
        // AssetLoader backed by a DefaultMediaSourceFactory. Nothing downloads.
        val httpFactory = OkHttpDataSource.Factory(okHttp).setUserAgent("ArchiveWatch-Android/1.0")
        val assetLoaderFactory =
            androidx.media3.transformer.DefaultAssetLoaderFactory(
                context,
                androidx.media3.transformer.DefaultDecoderFactory(context),
                androidx.media3.common.util.Clock.DEFAULT,
                DefaultMediaSourceFactory(httpFactory),
                androidx.media3.datasource.DataSourceBitmapLoader(context),
            )

        suspendCancellableCoroutine { cont ->
            val main = Handler(Looper.getMainLooper())
            // Transformer must be built + started on a Looper thread.
            main.post {
                val transformer = Transformer.Builder(context)
                    .setAssetLoaderFactory(assetLoaderFactory)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, result: ExportResult) {
                            onProgress(1.0)
                            if (cont.isActive) cont.resume(out)
                        }

                        override fun onError(
                            composition: Composition,
                            result: ExportResult,
                            exception: ExportException,
                        ) {
                            if (cont.isActive) {
                                cont.resumeWithException(
                                    ClipExportException.Failed(
                                        exception.message ?: "The clip couldn't be rendered.",
                                    ),
                                )
                            }
                        }
                    })
                    .build()

                // Poll progress while the export runs.
                val progressHolder = androidx.media3.transformer.ProgressHolder()
                val ticker = object : Runnable {
                    override fun run() {
                        if (!cont.isActive) return
                        val state = transformer.getProgress(progressHolder)
                        if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                            onProgress(progressHolder.progress / 100.0)
                        }
                        main.postDelayed(this, 200)
                    }
                }

                cont.invokeOnCancellation {
                    main.post {
                        main.removeCallbacks(ticker)
                        transformer.cancel()
                    }
                }

                try {
                    transformer.start(edited, out.absolutePath)
                    main.postDelayed(ticker, 200)
                } catch (e: Exception) {
                    if (cont.isActive) {
                        cont.resumeWithException(
                            ClipExportException.Failed(e.message ?: "Couldn't start the export."),
                        )
                    }
                }
            }
        }
        out
    }

    // MARK: Overlay (styled caption + credit) rendered to a bitmap

    @OptIn(UnstableApi::class)
    private fun makeOverlayEffect(
        canvas: Size,
        caption: String,
        credit: String,
        style: CaptionStyle,
    ): OverlayEffect {
        val bitmap = renderOverlayBitmap(canvas.width, canvas.height, caption, credit, style)
        // The bitmap is already laid out in canvas coordinates (the caption sits
        // at its normalized position, the credit bottom-center), so a centered
        // full-canvas overlay places everything exactly where it was drawn.
        val settings = StaticOverlaySettings.Builder().build()
        val overlay: TextureOverlay = BitmapOverlay.createStaticBitmapOverlay(bitmap, settings)
        return OverlayEffect(ImmutableList.of(overlay))
    }

    /**
     * Draw the styled caption (at its normalized position) + the always-on
     * provenance credit (small, bottom-centered) onto a transparent canvas-
     * sized bitmap. Self-contained Android Canvas so the burned-in text matches
     * the Compose live preview (WYSIWYG, parity with iOS b46).
     */
    fun renderOverlayBitmap(
        w: Int,
        h: Int,
        caption: String,
        credit: String,
        style: CaptionStyle,
    ): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)

        // Provenance credit — small, bottom-centered, always present.
        val creditPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(220, 255, 255, 255)
            textSize = maxOf(16f, w * 0.020f)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
            textAlign = Paint.Align.CENTER
            setShadowLayer(4f, 0f, 1f, Color.argb(230, 0, 0, 0))
        }
        canvas.drawText(
            ellipsize(credit, creditPaint, w * 0.92f),
            w / 2f,
            h - h * 0.030f,
            creditPaint,
        )

        if (caption.isNotEmpty()) {
            drawStyledCaption(canvas, w, h, caption, style)
        }
        return bmp
    }

    /**
     * Draw the caption centered on its normalized position with the chosen
     * font / size / color / background. Wraps to up to 3 lines at 86% width
     * (the iOS `renderCaptionImage` layout).
     */
    private fun drawStyledCaption(canvas: Canvas, w: Int, h: Int, caption: String, style: CaptionStyle) {
        val fontSize = maxOf(12f, w * 0.05f * style.size.scale)
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = style.color.argb
            textSize = fontSize
            typeface = style.font.typeface()
            textAlign = Paint.Align.CENTER
            if (style.background == CaptionBackground.SHADOW) {
                setShadowLayer(fontSize * 0.14f, 0f, fontSize * 0.04f, Color.argb(230, 0, 0, 0))
            }
        }
        val maxTextWidth = w * 0.86f
        val lines = wrapText(caption, paint, maxTextWidth, maxLines = 3)
        val lineHeight = paint.fontSpacing
        val textBlockHeight = lineHeight * lines.size

        val cx = style.posX * w
        val cy = style.posY * h

        // Box background sits behind the whole text block.
        if (style.background == CaptionBackground.BOX) {
            val padX = fontSize * 0.5f
            val padY = fontSize * 0.35f
            val widest = lines.maxOf { paint.measureText(it) }
            val boxW = (widest + padX * 2).coerceAtMost(w.toFloat())
            val boxH = textBlockHeight + padY * 2
            val boxPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(140, 0, 0, 0) }
            val rect = RectF(cx - boxW / 2, cy - boxH / 2, cx + boxW / 2, cy + boxH / 2)
            canvas.drawRoundRect(rect, fontSize * 0.4f, fontSize * 0.4f, boxPaint)
        }

        // First baseline so the block is vertically centered on cy.
        var baseline = cy - textBlockHeight / 2 - paint.ascent()
        for (line in lines) {
            canvas.drawText(line, cx, baseline, paint)
            baseline += lineHeight
        }
    }

    private fun ellipsize(text: String, paint: Paint, maxWidth: Float): String {
        if (paint.measureText(text) <= maxWidth) return text
        var s = text
        while (s.isNotEmpty() && paint.measureText("$s…") > maxWidth) {
            s = s.dropLast(1)
        }
        return "$s…"
    }

    private fun wrapText(text: String, paint: Paint, maxWidth: Float, maxLines: Int): List<String> {
        val words = text.split(' ')
        val lines = mutableListOf<String>()
        var current = StringBuilder()
        for (word in words) {
            val candidate = if (current.isEmpty()) word else "$current $word"
            if (paint.measureText(candidate) <= maxWidth || current.isEmpty()) {
                current = StringBuilder(candidate)
            } else {
                lines.add(current.toString())
                current = StringBuilder(word)
                if (lines.size == maxLines) break
            }
        }
        if (lines.size < maxLines && current.isNotEmpty()) lines.add(current.toString())
        if (lines.size == maxLines) {
            lines[maxLines - 1] = ellipsize(lines[maxLines - 1], paint, maxWidth)
        }
        return lines.ifEmpty { listOf("") }
    }
}

/** Oriented video size + duration probed off the remote stream. */
data class SourceInfo(val width: Int, val height: Int, val durationSeconds: Double)
