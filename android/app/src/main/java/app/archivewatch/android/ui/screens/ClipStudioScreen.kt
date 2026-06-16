package app.archivewatch.android.ui.screens

import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.data.ClipAspect
import app.archivewatch.android.data.ClipExporter
import app.archivewatch.android.data.ClipFormat
import app.archivewatch.android.data.ClipLook
import app.archivewatch.android.data.ClipSpec
import app.archivewatch.android.data.ClipSpeed
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.Nav
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

private enum class Phase { PREPARING, EDITING, EXPORTING, RESULT }

/**
 * Clip Studio — the Android content-creation surface (CREATE-STUDIO-PLAN §5,
 * Decision 033). A modal task: prepare the source, trim on a thumbnail
 * filmstrip, reframe + caption, export an MP4 via Media3 Transformer, then
 * save to MediaStore / share. The human makes every editorial choice; the
 * engine handles the mechanical work. Native Compose M3 throughout.
 *
 * GIF is omitted on Android v1 (no native encoder — PARITY gap); the format
 * is fixed to Video.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClipStudioScreen(container: AppContainer, nav: Nav, archiveID: String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val dbVersion by container.catalog.dbVersion.collectAsState()

    val item by produceState<CatalogItem?>(null, archiveID, dbVersion) {
        value = container.catalog.db?.item(archiveID)
    }

    var phase by remember { mutableStateOf(Phase.PREPARING) }
    var prepProgress by remember { mutableFloatStateOf(0f) }
    var exportProgress by remember { mutableFloatStateOf(0f) }
    var error by remember { mutableStateOf<String?>(null) }

    var localSource by remember { mutableStateOf<File?>(null) }
    var duration by remember { mutableDoubleStateOf(0.0) }
    val thumbnails = remember { mutableStateListOf<Bitmap>() }

    var inSeconds by remember { mutableDoubleStateOf(0.0) }
    var outSeconds by remember { mutableDoubleStateOf(15.0) }
    var aspect by remember { mutableStateOf(ClipAspect.VERTICAL) }
    var look by remember { mutableStateOf(ClipLook.NONE) }
    var speed by remember { mutableStateOf(ClipSpeed.ONE) }
    var caption by remember { mutableStateOf("") }
    var resultFile by remember { mutableStateOf<File?>(null) }
    var saved by remember { mutableStateOf(false) }
    var exportJob by remember { mutableStateOf<Job?>(null) }

    val clipDuration = (outSeconds - inSeconds).coerceAtLeast(0.0)
    val format = ClipFormat.VIDEO

    val current = item

    // Prepare: download the source, then read duration + thumbnails.
    LaunchedEffect(current?.archiveID) {
        val it = current ?: return@LaunchedEffect
        if (phase != Phase.PREPARING) return@LaunchedEffect
        val url = it.downloadURL
        if (url.isNullOrBlank()) {
            error = "This title has no video to clip."
            return@LaunchedEffect
        }
        try {
            val local = container.clipExporter.prepareSource(url, it.archiveID) { p ->
                prepProgress = p.toFloat()
            }
            localSource = local
            withContext(Dispatchers.IO) {
                val (dur, thumbs) = loadAsset(local)
                duration = dur
                outSeconds = minOf(dur, 15.0)
                thumbnails.clear()
                thumbnails.addAll(thumbs)
            }
            phase = Phase.EDITING
        } catch (e: Exception) {
            error = e.message ?: "Couldn't prepare the clip."
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Clip Studio") },
                navigationIcon = {
                    IconButton(onClick = { exportJob?.cancel(); nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Cancel")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                current == null -> LoadingBox()
                error != null && phase == Phase.PREPARING ->
                    EmptyState(error ?: "Couldn't prepare the clip.")
                else -> when (phase) {
                    Phase.PREPARING -> ProgressPhase(prepProgress, "Preparing clip…", current.title)
                    Phase.EXPORTING -> ProgressPhase(exportProgress, "Rendering ${format.label}…", null)
                    Phase.EDITING -> EditingPhase(
                        item = current,
                        thumbnails = thumbnails,
                        duration = duration,
                        inSeconds = inSeconds,
                        outSeconds = outSeconds,
                        clipDuration = clipDuration,
                        aspect = aspect,
                        look = look,
                        speed = speed,
                        caption = caption,
                        error = error,
                        canExport = clipDuration >= 0.5 && localSource != null,
                        onTrim = { newIn, newOut -> inSeconds = newIn; outSeconds = newOut },
                        onAspect = { aspect = it },
                        onLook = { look = it },
                        onSpeed = { speed = it },
                        onCaption = { caption = it },
                        onExport = {
                            val local = localSource ?: return@EditingPhase
                            error = null
                            phase = Phase.EXPORTING
                            exportProgress = 0f
                            exportJob = scope.launch {
                                try {
                                    val spec = ClipSpec(
                                        sourceFile = local,
                                        archiveID = current.archiveID,
                                        title = current.title,
                                        sourceDetailsURL = current.sourceDetailsURL,
                                        creditLine = current.clipCreditLine,
                                        inSeconds = inSeconds,
                                        durationSeconds = clipDuration,
                                        aspect = aspect,
                                        caption = caption.trim(),
                                        format = format,
                                        look = look,
                                        speed = speed,
                                    )
                                    val out = container.clipExporter.exportVideo(spec) { p ->
                                        exportProgress = p.toFloat()
                                    }
                                    resultFile = out
                                    container.userState.saveClip(
                                        sourceArchiveID = current.archiveID,
                                        sourceTitle = current.title,
                                        inSeconds = inSeconds,
                                        durationSeconds = clipDuration,
                                        aspect = aspect.name,
                                        format = format.name,
                                        caption = caption.trim(),
                                        renderFilename = out.name,
                                    )
                                    phase = Phase.RESULT
                                } catch (e: Exception) {
                                    error = e.message ?: "The clip couldn't be rendered."
                                    phase = Phase.EDITING
                                }
                            }
                        },
                    )
                    Phase.RESULT -> ResultPhase(
                        resultFile = resultFile,
                        aspect = aspect,
                        creditLine = current.clipCreditLine,
                        title = current.title,
                        saved = saved,
                        onSave = {
                            val out = resultFile ?: return@ResultPhase
                            scope.launch {
                                val ok = withContext(Dispatchers.IO) {
                                    saveToGallery(context, out)
                                }
                                if (ok) saved = true else error = "Couldn't save to your gallery."
                            }
                        },
                        onShare = {
                            val out = resultFile ?: return@ResultPhase
                            shareClip(context, out)
                        },
                        onMakeAnother = { saved = false; phase = Phase.EDITING },
                        onDone = { nav.pop() },
                    )
                }
            }
        }
    }
}

@Composable
private fun ProgressPhase(progress: Float, label: String, subtitle: String?) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        if (progress > 0f) {
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth(0.7f),
            )
        } else {
            CircularProgressIndicator()
        }
        Spacer(Modifier.height(16.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium,
             color = MaterialTheme.colorScheme.onSurfaceVariant)
        subtitle?.let {
            Spacer(Modifier.height(4.dp))
            Text(it, style = MaterialTheme.typography.bodySmall,
                 color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EditingPhase(
    item: CatalogItem,
    thumbnails: List<Bitmap>,
    duration: Double,
    inSeconds: Double,
    outSeconds: Double,
    clipDuration: Double,
    aspect: ClipAspect,
    look: ClipLook,
    speed: ClipSpeed,
    caption: String,
    error: String?,
    canExport: Boolean,
    onTrim: (Double, Double) -> Unit,
    onAspect: (ClipAspect) -> Unit,
    onLook: (ClipLook) -> Unit,
    onSpeed: (ClipSpeed) -> Unit,
    onCaption: (String) -> Unit,
    onExport: () -> Unit,
) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        // Preview frame (first thumbnail under the chosen aspect, caption +
        // credit composited in the preview as a hint — the export burns them).
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(aspect.ratio ?: (16f / 9f))
                .clip(RoundedCornerShape(12.dp))
                .background(Color.Black),
            contentAlignment = Alignment.Center,
        ) {
            thumbnails.firstOrNull()?.let {
                Image(
                    bitmap = it.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            Column(
                Modifier.fillMaxSize().padding(8.dp),
                verticalArrangement = Arrangement.Bottom,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (caption.isNotEmpty()) {
                    Text(
                        caption,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.titleMedium,
                    )
                }
                Spacer(Modifier.height(4.dp))
                Text(
                    item.clipCreditLine,
                    color = Color.White.copy(alpha = 0.85f),
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }

        // Trim timeline (custom — no native Android trimmer; plan §5b).
        TrimStrip(
            thumbnails = thumbnails,
            duration = duration,
            inSeconds = inSeconds,
            outSeconds = outSeconds,
            maxClip = ClipFormat.VIDEO.maxDuration,
            onTrim = onTrim,
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(timecode(inSeconds), style = MaterialTheme.typography.labelMedium,
                 color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(String.format("%.1fs", clipDuration), style = MaterialTheme.typography.labelMedium,
                 fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            Text(timecode(outSeconds), style = MaterialTheme.typography.labelMedium,
                 color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        // Frame (aspect) picker — native SegmentedButton.
        LabeledSection("Frame") {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                ClipAspect.entries.forEachIndexed { i, a ->
                    SegmentedButton(
                        selected = aspect == a,
                        onClick = { onAspect(a) },
                        shape = SegmentedButtonDefaults.itemShape(i, ClipAspect.entries.size),
                    ) { Text(a.label) }
                }
            }
        }

        // Color-grade Look picker — native SegmentedButton (6 short labels,
        // mirrors iOS ClipLook). Grade is applied to the source frames at export.
        LabeledSection("Look") {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                ClipLook.entries.forEachIndexed { i, l ->
                    SegmentedButton(
                        selected = look == l,
                        onClick = { onLook(l) },
                        shape = SegmentedButtonDefaults.itemShape(i, ClipLook.entries.size),
                    ) { Text(l.label, maxLines = 1) }
                }
            }
        }

        // Speed picker — native SegmentedButton (0.5× / 1× / 2×, A/V together).
        LabeledSection("Speed") {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                ClipSpeed.entries.forEachIndexed { i, s ->
                    SegmentedButton(
                        selected = speed == s,
                        onClick = { onSpeed(s) },
                        shape = SegmentedButtonDefaults.itemShape(i, ClipSpeed.entries.size),
                    ) { Text(s.label) }
                }
            }
        }

        // Caption entry — native TextField.
        LabeledSection("Caption") {
            OutlinedTextField(
                value = caption,
                onValueChange = onCaption,
                placeholder = { Text("Add a caption (optional)") },
                modifier = Modifier.fillMaxWidth(),
                maxLines = 2,
            )
        }

        error?.let {
            Text(it, color = MaterialTheme.colorScheme.error,
                 style = MaterialTheme.typography.bodySmall)
        }

        Button(
            onClick = onExport,
            enabled = canExport,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(Icons.Default.AutoAwesome, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text("Create ${ClipFormat.VIDEO.label}")
        }

        Text(
            "Clips carry an archivewatch.org · public-domain credit and the source link in their file metadata. Source: ${item.title}.",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun ResultPhase(
    resultFile: File?,
    aspect: ClipAspect,
    creditLine: String,
    title: String,
    saved: Boolean,
    onSave: () -> Unit,
    onShare: () -> Unit,
    onMakeAnother: () -> Unit,
    onDone: () -> Unit,
) {
    val frame = remember(resultFile) { resultFile?.let { firstFrame(it) } }
    Column(
        Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(aspect.ratio ?: (16f / 9f))
                .clip(RoundedCornerShape(12.dp))
                .background(Color.Black),
            contentAlignment = Alignment.Center,
        ) {
            frame?.let {
                Image(
                    bitmap = it.asImageBitmap(),
                    contentDescription = "Clip preview",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = onSave, enabled = !saved, modifier = Modifier.weight(1f)) {
                Icon(Icons.Default.Download, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(if (saved) "Saved" else "Save")
            }
            Button(onClick = onShare, modifier = Modifier.weight(1f)) {
                Icon(Icons.Default.Share, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Share")
            }
        }
        TextButton(onClick = onMakeAnother) { Text("Make another") }
        Text(
            "Clips carry an archivewatch.org · public-domain credit. Source: $title.",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        TextButton(onClick = onDone) { Text("Done") }
    }
}

@Composable
private fun LabeledSection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            title.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        content()
    }
}

/**
 * Two-handle trim selection over a thumbnail filmstrip. The custom layer
 * (no native Android trimmer — plan §5b) only positions two draggable handles
 * over native MediaMetadataRetriever thumbnails and reports in/out times.
 */
@Composable
private fun TrimStrip(
    thumbnails: List<Bitmap>,
    duration: Double,
    inSeconds: Double,
    outSeconds: Double,
    maxClip: Double,
    onTrim: (Double, Double) -> Unit,
) {
    val density = LocalDensity.current
    var widthPx by remember { mutableFloatStateOf(0f) }
    val stripHeight = 56.dp
    val safeDur = duration.coerceAtLeast(0.001)

    Box(
        Modifier
            .fillMaxWidth()
            .height(stripHeight)
            .clip(RoundedCornerShape(8.dp))
            .background(Color.Black)
            .onSizeChanged { widthPx = it.width.toFloat() }
            .pointerInput(duration, maxClip, inSeconds, outSeconds) {
                detectHorizontalDragGestures { change, _ ->
                    val w = size.width.toFloat()
                    if (w <= 0f) return@detectHorizontalDragGestures
                    val inX = (inSeconds / safeDur * w).toFloat()
                    val outX = (outSeconds / safeDur * w).toFloat()
                    val x = change.position.x
                    val raw = (x / w * duration)
                    // Move the nearer handle (clamped to a 0.5s min + format cap).
                    if (kotlin.math.abs(x - inX) <= kotlin.math.abs(x - outX)) {
                        val t = raw.coerceIn(0.0, outSeconds - 0.5)
                        val clamped = maxOf(t, outSeconds - maxClip)
                        onTrim(clamped, outSeconds)
                    } else {
                        val t = raw.coerceIn(inSeconds + 0.5, duration)
                        val clamped = minOf(t, inSeconds + maxClip)
                        onTrim(inSeconds, clamped)
                    }
                }
            },
    ) {
        // Filmstrip
        Row(Modifier.fillMaxSize()) {
            val n = thumbnails.size.coerceAtLeast(1)
            thumbnails.forEach { bmp ->
                Image(
                    bitmap = bmp.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().weight(1f / n),
                )
            }
        }

        val w = widthPx
        if (w > 0f) {
            val inX = (inSeconds / safeDur * w).toFloat()
            val outX = (outSeconds / safeDur * w).toFloat()
            // Dim outside the selection.
            Box(
                Modifier
                    .width(with(density) { inX.coerceAtLeast(0f).toDp() })
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.55f)),
            )
            Box(
                Modifier
                    .offset(x = with(density) { outX.toDp() })
                    .width(with(density) { (w - outX).coerceAtLeast(0f).toDp() })
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.55f)),
            )
            // Selection outline + two handles.
            Box(
                Modifier
                    .offset(x = with(density) { inX.toDp() })
                    .width(with(density) { (outX - inX).coerceAtLeast(0f).toDp() })
                    .fillMaxSize()
                    .background(Color.Transparent)
                    .border(3.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(6.dp)),
            )
            HandleBar(Modifier.offset(x = with(density) { (inX - 8f).toDp() }))
            HandleBar(Modifier.offset(x = with(density) { (outX - 8f).toDp() }))
        }
    }
}

@Composable
private fun HandleBar(modifier: Modifier) {
    Box(
        modifier
            .width(16.dp)
            .fillMaxSize()
            .clip(RoundedCornerShape(4.dp))
            .background(MaterialTheme.colorScheme.primary),
    )
}

// MARK: Asset helpers (off the main thread)

/** Read clip duration + a 12-thumbnail filmstrip from a local file. */
private fun loadAsset(file: File): Pair<Double, List<Bitmap>> {
    val retriever = MediaMetadataRetriever()
    return try {
        retriever.setDataSource(file.absolutePath)
        val durMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        val duration = durMs / 1000.0
        val thumbs = mutableListOf<Bitmap>()
        if (duration > 0) {
            val n = 12
            for (i in 0 until n) {
                val tUs = (duration * i / n * 1_000_000).toLong()
                retriever.getFrameAtTime(tUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)?.let {
                    // Downscale for the strip.
                    thumbs.add(Bitmap.createScaledBitmap(it, 160, (160 * it.height / it.width).coerceAtLeast(1), true))
                }
            }
        }
        Pair(duration, thumbs)
    } catch (_: Exception) {
        Pair(0.0, emptyList())
    } finally {
        runCatching { retriever.release() }
    }
}

private fun firstFrame(file: File): Bitmap? {
    val retriever = MediaMetadataRetriever()
    return try {
        retriever.setDataSource(file.absolutePath)
        retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
    } catch (_: Exception) {
        null
    } finally {
        runCatching { retriever.release() }
    }
}

/** Save an exported MP4 to the device gallery via MediaStore. */
private fun saveToGallery(context: android.content.Context, file: File): Boolean {
    return try {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, file.name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/ArchiveWatch")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
        }
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }
        val uri = resolver.insert(collection, values) ?: return false
        resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
            ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }
        true
    } catch (_: Exception) {
        false
    }
}

/** Share an exported clip via ACTION_SEND + FileProvider. */
private fun shareClip(context: android.content.Context, file: File) {
    val uri: Uri = androidx.core.content.FileProvider.getUriForFile(
        context, "${context.packageName}.fileprovider", file,
    )
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "video/mp4"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_TEXT, "Clipped from archive.org with Archive Watch · archivewatch.org")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(send, null))
}

private fun timecode(s: Double): String {
    val total = s.toInt()
    return String.format("%d:%02d", total / 60, total % 60)
}
