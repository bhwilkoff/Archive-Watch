package app.archivewatch.android.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.text.TextPaint
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextureOverlay
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
import okhttp3.Request
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
 * Editing operates on a LOCAL file (the research's robust path — a complete
 * moov-bearing file gives predictable behavior, unlike the play-as-you-go
 * range stream the player uses). The engine downloads the source to cacheDir
 * first, then trims / reframes / overlays / encodes. Exports are serialized
 * (one hardware video encoder; concurrent sessions contend + overheat).
 *
 * GIF: Android has NO native GIF encoder, so v1 ships MP4 only — the GIF gap
 * is documented in PARITY (WebP / a vendored encoder is a later option; we do
 * NOT add a third-party GIF lib).
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

data class ClipSpec(
    val sourceFile: File,
    val archiveID: String,
    val title: String,
    val sourceDetailsURL: String,
    val creditLine: String,
    val inSeconds: Double,
    val durationSeconds: Double,
    val aspect: ClipAspect,
    val caption: String,
    val format: ClipFormat,
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
    private val sourcesDir: File
        get() = File(context.cacheDir, "clip-sources").apply { mkdirs() }

    fun renderFile(filename: String): File = File(clipsDir, filename)

    // MARK: Source acquisition

    /**
     * Download the full source MP4 to cacheDir (the editor needs a complete
     * local file). Cached, so re-editing the same film is instant. v2:
     * range-download just the clip window keyed on the moov index.
     */
    suspend fun prepareSource(
        remoteURL: String,
        archiveID: String,
        onProgress: (Double) -> Unit,
    ): File = withContext(Dispatchers.IO) {
        val safe = archiveID.replace('/', '_')
        val dest = File(sourcesDir, "$safe.mp4")
        if (dest.exists() && dest.length() > 0) {
            onProgress(1.0)
            return@withContext dest
        }
        val request = Request.Builder()
            .url(remoteURL)
            .header("User-Agent", "ArchiveWatch-Android/1.0")
            .build()
        okHttp.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw ClipExportException.Failed("Couldn't download the source (HTTP ${response.code}).")
            }
            val body = response.body ?: throw ClipExportException.Failed("Empty response from the source.")
            val total = body.contentLength()
            val tmp = File(sourcesDir, "$safe.part")
            body.byteStream().use { input ->
                tmp.outputStream().use { output ->
                    val buf = ByteArray(64 * 1024)
                    var written = 0L
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        output.write(buf, 0, n)
                        written += n
                        if (total > 0) onProgress(written.toDouble() / total)
                    }
                }
            }
            if (dest.exists()) dest.delete()
            if (!tmp.renameTo(dest)) {
                tmp.copyTo(dest, overwrite = true)
                tmp.delete()
            }
        }
        onProgress(1.0)
        dest
    }

    // MARK: Video export (trim + reframe + caption + credit)

    suspend fun exportVideo(
        spec: ClipSpec,
        onProgress: (Double) -> Unit,
    ): File = exportMutex.withLock {
        val (srcW, srcH) = orientedSize(spec.sourceFile)
            ?: throw ClipExportException.NoVideoTrack
        val renderSize = spec.aspect.renderSize(srcW, srcH)

        val out = File(clipsDir, "ArchiveWatch-${UUID.randomUUID().toString().take(8)}.mp4")
        if (out.exists()) out.delete()

        // Trim window. Media3 ClippingConfiguration uses millis on the source
        // timeline; positiveAndZero clamps a slightly-overrun out-point.
        val startMs = (spec.inSeconds * 1000).toLong()
        val endMs = ((spec.inSeconds + spec.durationSeconds) * 1000).toLong()

        val mediaItem = MediaItem.Builder()
            .setUri(android.net.Uri.fromFile(spec.sourceFile))
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .build(),
            )
            .build()

        val effects = mutableListOf<Effect>()
        // Reframe to the chosen canvas (letterbox/pillarbox into the matte).
        if (spec.aspect != ClipAspect.ORIGINAL) {
            effects.add(
                Presentation.createForWidthAndHeight(
                    renderSize.width, renderSize.height, Presentation.LAYOUT_SCALE_TO_FIT,
                ),
            )
        }
        // Always-on provenance credit + optional caption, burned in as a
        // single bitmap overlay sized to the render canvas.
        effects.add(makeOverlayEffect(renderSize, spec.caption, spec.creditLine))

        val edited = EditedMediaItem.Builder(mediaItem)
            .setEffects(Effects(ImmutableList.of(), ImmutableList.copyOf(effects)))
            .build()

        suspendCancellableCoroutine { cont ->
            val main = Handler(Looper.getMainLooper())
            // Transformer must be built + started on a Looper thread.
            main.post {
                val transformer = Transformer.Builder(context)
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

    // MARK: Overlay (caption + credit) rendered to a bitmap

    @OptIn(UnstableApi::class)
    private fun makeOverlayEffect(canvas: Size, caption: String, credit: String): OverlayEffect {
        val bitmap = renderOverlayBitmap(canvas.width, canvas.height, caption, credit)
        // Centered, full-canvas overlay (the bitmap is already laid out in
        // canvas coordinates, transparent except the text).
        val settings = StaticOverlaySettings.Builder().build()
        val overlay: TextureOverlay = BitmapOverlay.createStaticBitmapOverlay(bitmap, settings)
        return OverlayEffect(ImmutableList.of(overlay))
    }

    /**
     * Draw the caption (lower-third, title-safe) + the always-on provenance
     * credit (small, bottom-centered) onto a transparent canvas-sized bitmap.
     * Self-contained Android Canvas so the burned-in text matches the iOS
     * Core Animation overlay path.
     */
    private fun renderOverlayBitmap(w: Int, h: Int, caption: String, credit: String): Bitmap {
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
            val capPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = maxOf(30f, w * 0.050f)
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                textAlign = Paint.Align.CENTER
                setShadowLayer(4f, 0f, 1f, Color.argb(230, 0, 0, 0))
            }
            // Up to two lines, lower-third.
            val lines = wrapText(caption, capPaint, w * 0.88f, maxLines = 2)
            val lineHeight = capPaint.fontSpacing
            var baseline = h - h * 0.12f - (lines.size - 1) * lineHeight
            for (line in lines) {
                canvas.drawText(line, w / 2f, baseline, capPaint)
                baseline += lineHeight
            }
        }
        return bmp
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
        // Truncate the last line if there's overflow.
        if (lines.size == maxLines) {
            lines[maxLines - 1] = ellipsize(lines[maxLines - 1], paint, maxWidth)
        }
        return lines.ifEmpty { listOf("") }
    }

    /** Oriented (rotation-applied) video size from the source file. */
    private fun orientedSize(file: File): Pair<Int, Int>? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            val h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            val rot = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (w == null || h == null) return null
            if (rot == 90 || rot == 270) Pair(h, w) else Pair(w, h)
        } catch (_: Exception) {
            null
        } finally {
            runCatching { retriever.release() }
        }
    }
}
