package app.archivewatch.android.ui.screens

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.annotation.OptIn
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.material.icons.filled.PlayCircle
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
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CaptionBackground
import app.archivewatch.android.data.CaptionColor
import app.archivewatch.android.data.CaptionFont
import app.archivewatch.android.data.CaptionSize
import app.archivewatch.android.data.CaptionStyle
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.data.ClipAspect
import app.archivewatch.android.data.ClipFormat
import app.archivewatch.android.data.ClipLook
import app.archivewatch.android.data.ClipSpec
import app.archivewatch.android.data.ClipSpeed
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.ClipTimeline
import app.archivewatch.android.ui.Nav
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

private enum class Phase { PREPARING, EDITING, EXPORTING, RESULT }

/**
 * Clip Studio — the Android content-creation surface (CREATE-STUDIO-PLAN §5,
 * Decision 033). A modal task: open the remote film, trim on a CapCut-style
 * scrolling timeline, reframe + grade + caption (styled, draggable, WYSIWYG),
 * export an MP4 via Media3 Transformer, then save to MediaStore / share. The
 * human makes every editorial choice; the engine handles the mechanical work.
 * Native Compose M3 + Media3 throughout.
 *
 * STREAM, DON'T DOWNLOAD (parity with iOS b44): the preview ExoPlayer, the
 * filmstrip thumbnails, and the Transformer source all read the REMOTE
 * archive.org URL directly over ranged HTTP — nothing is downloaded.
 *
 * GIF is omitted on Android (no native encoder — PARITY / ANDROID-DESIGN gap);
 * the format is fixed to Video.
 */
@OptIn(ExperimentalMaterial3Api::class, UnstableApi::class)
@Composable
fun ClipStudioScreen(container: AppContainer, nav: Nav, archiveID: String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val dbVersion by container.catalog.dbVersion.collectAsState()

    val item by produceState<CatalogItem?>(null, archiveID, dbVersion) {
        value = container.catalog.db?.item(archiveID)
    }

    var phase by remember { mutableStateOf(Phase.PREPARING) }
    var exportProgress by remember { mutableFloatStateOf(0f) }
    var error by remember { mutableStateOf<String?>(null) }

    var sourceURL by remember { mutableStateOf<String?>(null) }
    var duration by remember { mutableDoubleStateOf(0.0) }
    val thumbnails = remember { mutableStateListOf<Bitmap?>() }

    var inSeconds by remember { mutableDoubleStateOf(0.0) }
    var outSeconds by remember { mutableDoubleStateOf(15.0) }
    var playhead by remember { mutableDoubleStateOf(0.0) }
    var isPlaying by remember { mutableStateOf(false) }
    var aspect by remember { mutableStateOf(ClipAspect.VERTICAL) }
    var look by remember { mutableStateOf(ClipLook.NONE) }
    var speed by remember { mutableStateOf(ClipSpeed.ONE) }
    var caption by remember { mutableStateOf("") }
    var captionStyle by remember { mutableStateOf(CaptionStyle()) }
    var resultFile by remember { mutableStateOf<File?>(null) }
    var saved by remember { mutableStateOf(false) }
    var exportJob by remember { mutableStateOf<Job?>(null) }

    val clipDuration = (outSeconds - inSeconds).coerceAtLeast(0.0)
    val format = ClipFormat.VIDEO
    val current = item

    // The preview player streams the remote source directly (no download). Built
    // once per source URL; controls-free — the timeline is the only scrubber.
    val player = remember(sourceURL) {
        val url = sourceURL ?: return@remember null
        val httpFactory = OkHttpDataSource.Factory(container.okHttp)
            .setUserAgent("ArchiveWatch-Android/1.0")
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(httpFactory))
            .build()
            .apply {
                setMediaItem(MediaItem.fromUri(url))
                playWhenReady = false
                prepare()
            }
    }
    DisposableEffect(player) {
        onDispose { player?.release() }
    }

    // Reflect ExoPlayer play state changes (e.g. ended) into our isPlaying flag.
    DisposableEffect(player) {
        val p = player ?: return@DisposableEffect onDispose {}
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) { isPlaying = playing }
        }
        p.addListener(listener)
        onDispose { p.removeListener(listener) }
    }

    // While playing, drive the playhead from the player and stop at the out point.
    LaunchedEffect(isPlaying, player) {
        val p = player ?: return@LaunchedEffect
        while (isActive && isPlaying) {
            val s = p.currentPosition / 1000.0
            playhead = s
            if (s >= outSeconds) {
                p.pause()
                p.seekTo((outSeconds * 1000).toLong())
                playhead = outSeconds
                isPlaying = false
            }
            delay(33)
        }
    }

    // Prepare: probe the remote stream for size/duration, then stream thumbnails.
    LaunchedEffect(current?.archiveID) {
        val it = current ?: return@LaunchedEffect
        if (phase != Phase.PREPARING) return@LaunchedEffect
        val url = it.downloadURL
        if (url.isNullOrBlank()) {
            error = "This title has no video to clip."
            return@LaunchedEffect
        }
        try {
            val info = container.clipExporter.probeSource(url)
                ?: throw IllegalStateException("This title has no video to clip.")
            sourceURL = url
            duration = info.durationSeconds
            outSeconds = minOf(info.durationSeconds.takeIf { d -> d > 0 } ?: 15.0, 15.0)
            val n = 40
            repeat(n) { thumbnails.add(null) }
            phase = Phase.EDITING
            // Fill the filmstrip progressively off the stream.
            container.clipExporter.streamThumbnails(url, info.durationSeconds, n) { idx, bmp ->
                if (idx < thumbnails.size) thumbnails[idx] = bmp
            }
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
                    Phase.PREPARING -> ProgressPhase(0f, "Loading clip…", current.title)
                    Phase.EXPORTING -> ProgressPhase(exportProgress, "Rendering ${format.label}…", null)
                    Phase.EDITING -> EditingPhase(
                        item = current,
                        player = player,
                        thumbnails = thumbnails,
                        duration = duration,
                        inSeconds = inSeconds,
                        outSeconds = outSeconds,
                        playhead = playhead,
                        isPlaying = isPlaying,
                        clipDuration = clipDuration,
                        outputDuration = if (speed.multiplier > 0) clipDuration / speed.multiplier else clipDuration,
                        aspect = aspect,
                        look = look,
                        speed = speed,
                        caption = caption,
                        captionStyle = captionStyle,
                        error = error,
                        canExport = clipDuration >= 0.5 && sourceURL != null,
                        onScrub = { t ->
                            player?.let {
                                if (isPlaying) it.pause()
                                playhead = t.coerceIn(0.0, duration)
                                it.seekTo((playhead * 1000).toLong())
                            }
                        },
                        onTogglePlay = {
                            val p = player ?: return@EditingPhase
                            if (isPlaying) {
                                p.pause()
                            } else {
                                if (playhead < inSeconds || playhead >= outSeconds - 0.05) {
                                    playhead = inSeconds
                                    p.seekTo((inSeconds * 1000).toLong())
                                }
                                p.play()
                            }
                        },
                        onSetStart = {
                            inSeconds = playhead.coerceIn(0.0, outSeconds - 0.5)
                            if (clipDuration > format.maxDuration) outSeconds = inSeconds + format.maxDuration
                        },
                        onSetEnd = {
                            outSeconds = playhead.coerceIn(inSeconds + 0.5, duration)
                            if (clipDuration > format.maxDuration) inSeconds = outSeconds - format.maxDuration
                        },
                        onTrim = { newIn, newOut, previewAt ->
                            player?.let { if (isPlaying) it.pause() }
                            inSeconds = newIn
                            outSeconds = newOut
                            playhead = previewAt
                            player?.seekTo((previewAt * 1000).toLong())
                        },
                        onAspect = { aspect = it },
                        onLook = { look = it },
                        onSpeed = { speed = it },
                        onCaption = { caption = it },
                        onCaptionStyle = { captionStyle = it },
                        onExport = {
                            val url = sourceURL ?: return@EditingPhase
                            error = null
                            player?.pause()
                            phase = Phase.EXPORTING
                            exportProgress = 0f
                            exportJob = scope.launch {
                                try {
                                    val spec = ClipSpec(
                                        sourceURL = url,
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
                                        captionStyle = captionStyle,
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
                        title = current.title,
                        saved = saved,
                        onSave = {
                            val out = resultFile ?: return@ResultPhase
                            scope.launch {
                                val ok = withContext(Dispatchers.IO) { saveToGallery(context, out) }
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
            LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth(0.7f))
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

@OptIn(ExperimentalMaterial3Api::class, UnstableApi::class)
@Composable
private fun EditingPhase(
    item: CatalogItem,
    player: ExoPlayer?,
    thumbnails: List<Bitmap?>,
    duration: Double,
    inSeconds: Double,
    outSeconds: Double,
    playhead: Double,
    isPlaying: Boolean,
    clipDuration: Double,
    outputDuration: Double,
    aspect: ClipAspect,
    look: ClipLook,
    speed: ClipSpeed,
    caption: String,
    captionStyle: CaptionStyle,
    error: String?,
    canExport: Boolean,
    onScrub: (Double) -> Unit,
    onTogglePlay: () -> Unit,
    onSetStart: () -> Unit,
    onSetEnd: () -> Unit,
    onTrim: (Double, Double, Double) -> Unit,
    onAspect: (ClipAspect) -> Unit,
    onLook: (ClipLook) -> Unit,
    onSpeed: (ClipSpeed) -> Unit,
    onCaption: (String) -> Unit,
    onCaptionStyle: (CaptionStyle) -> Unit,
    onExport: () -> Unit,
) {
    val hasCaption = caption.isNotEmpty()
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Controls-free streaming preview + draggable styled caption overlay.
        CaptionedPreview(
            player = player,
            aspect = aspect,
            creditLine = item.clipCreditLine,
            caption = caption,
            captionStyle = captionStyle,
            isPlaying = isPlaying,
            onTogglePlay = onTogglePlay,
            onCaptionMove = { x, y -> onCaptionStyle(captionStyle.copy(posX = x, posY = y)) },
        )

        // Playhead / clip-length / total readout.
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(timecode(playhead), style = MaterialTheme.typography.labelMedium, color = Color.White)
            Text(
                if (speed == ClipSpeed.ONE) String.format("Clip %.1fs", clipDuration)
                else String.format("Clip %.1fs→%.1fs", clipDuration, outputDuration),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(timecode(duration), style = MaterialTheme.typography.labelMedium,
                 color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        // CapCut timeline: scroll the filmstrip under a fixed center playhead to
        // scrub, pinch to zoom, mark Set Start/End or drag the band handles.
        ClipTimeline(
            thumbnails = thumbnails,
            duration = duration,
            inSeconds = inSeconds,
            outSeconds = outSeconds,
            playhead = playhead,
            isPlaying = isPlaying,
            maxClip = ClipFormat.VIDEO.maxDuration,
            onScrub = onScrub,
            onTrim = onTrim,
            modifier = Modifier.fillMaxWidth().height(76.dp),
        )

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = onSetStart, modifier = Modifier.weight(1f)) { Text("Set Start") }
            OutlinedButton(onClick = onSetEnd, modifier = Modifier.weight(1f)) { Text("Set End") }
        }
        Text(
            "Drag the filmstrip to scrub · pinch to zoom · mark Set Start/End at the playhead, or drag the handles.",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )

        // Frame (aspect) picker.
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

        // Color-grade Look picker (6 short labels, mirrors iOS ClipLook).
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

        // Speed picker (0.5× / 1× / 2×, A/V together).
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

        // Caption entry + (once typed) style controls.
        LabeledSection("Caption") {
            OutlinedTextField(
                value = caption,
                onValueChange = onCaption,
                placeholder = { Text("Add a caption (optional)") },
                modifier = Modifier.fillMaxWidth(),
                maxLines = 2,
            )
            if (hasCaption) {
                // Font
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    CaptionFont.entries.forEachIndexed { i, f ->
                        SegmentedButton(
                            selected = captionStyle.font == f,
                            onClick = { onCaptionStyle(captionStyle.copy(font = f)) },
                            shape = SegmentedButtonDefaults.itemShape(i, CaptionFont.entries.size),
                        ) { Text(f.label, maxLines = 1) }
                    }
                }
                // Size + Color
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    SingleChoiceSegmentedButtonRow(Modifier.weight(1f)) {
                        CaptionSize.entries.forEachIndexed { i, s ->
                            SegmentedButton(
                                selected = captionStyle.size == s,
                                onClick = { onCaptionStyle(captionStyle.copy(size = s)) },
                                shape = SegmentedButtonDefaults.itemShape(i, CaptionSize.entries.size),
                            ) { Text(s.label) }
                        }
                    }
                    SingleChoiceSegmentedButtonRow(Modifier.weight(1.6f)) {
                        CaptionColor.entries.forEachIndexed { i, c ->
                            SegmentedButton(
                                selected = captionStyle.color == c,
                                onClick = { onCaptionStyle(captionStyle.copy(color = c)) },
                                shape = SegmentedButtonDefaults.itemShape(i, CaptionColor.entries.size),
                            ) { Text(c.label, maxLines = 1) }
                        }
                    }
                }
                // Background
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    CaptionBackground.entries.forEachIndexed { i, b ->
                        SegmentedButton(
                            selected = captionStyle.background == b,
                            onClick = { onCaptionStyle(captionStyle.copy(background = b)) },
                            shape = SegmentedButtonDefaults.itemShape(i, CaptionBackground.entries.size),
                        ) { Text(b.label, maxLines = 1) }
                    }
                }
                Text(
                    "Drag the caption on the preview to place it (on the video or in the bars).",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }

        Button(onClick = onExport, enabled = canExport, modifier = Modifier.fillMaxWidth()) {
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

/**
 * Controls-free streaming preview (PlayerView, useController=false) with a
 * draggable Compose caption overlay in the chosen style (WYSIWYG — the preview
 * box shares the export aspect, so where the caption sits here is where it
 * burns in). Tap the surface to play/pause the selection.
 */
@OptIn(UnstableApi::class)
@Composable
private fun CaptionedPreview(
    player: ExoPlayer?,
    aspect: ClipAspect,
    creditLine: String,
    caption: String,
    captionStyle: CaptionStyle,
    isPlaying: Boolean,
    onTogglePlay: () -> Unit,
    onCaptionMove: (Float, Float) -> Unit,
) {
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .aspectRatio(aspect.ratio ?: (16f / 9f))
            .clip(RoundedCornerShape(12.dp))
            .background(Color.Black)
            .pointerInput(Unit) { detectTapGestures(onTap = { onTogglePlay() }) },
    ) {
        val boxW = constraints.maxWidth.toFloat()
        val boxH = constraints.maxHeight.toFloat()
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    useController = false
                    setBackgroundColor(android.graphics.Color.BLACK)
                }
            },
            update = { it.player = player },
            modifier = Modifier.fillMaxSize(),
        )

        // Provenance credit — pinned bottom-center (always present).
        Text(
            creditLine,
            color = Color.White.copy(alpha = 0.85f),
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 6.dp),
        )

        // Draggable styled caption.
        if (caption.isNotEmpty()) {
            CaptionOverlay(
                text = caption,
                style = captionStyle,
                boxW = boxW,
                boxH = boxH,
                onMove = onCaptionMove,
            )
        }

        // Play affordance when paused.
        if (!isPlaying) {
            Icon(
                Icons.Default.PlayCircle,
                contentDescription = "Play",
                tint = Color.White.copy(alpha = 0.85f),
                modifier = Modifier.align(Alignment.Center).width(50.dp).height(50.dp),
            )
        }
    }
}

@Composable
private fun CaptionOverlay(
    text: String,
    style: CaptionStyle,
    boxW: Float,
    boxH: Float,
    onMove: (Float, Float) -> Unit,
) {
    val density = LocalDensity.current
    val fontSizeSp = with(density) { (boxW * 0.05f * style.size.scale).coerceAtLeast(11f).toSp() }
    val fontFamily = when (style.font) {
        CaptionFont.SANS -> FontFamily.SansSerif
        CaptionFont.ROUND -> FontFamily.SansSerif
        CaptionFont.SERIF -> FontFamily.Serif
        CaptionFont.MONO -> FontFamily.Monospace
    }
    val color = when (style.color) {
        CaptionColor.WHITE -> Color.White
        CaptionColor.YELLOW -> Color(0xFFFFD60A)
        CaptionColor.BLACK -> Color.Black
    }

    // Position is the normalized CENTER; offset by half the measured size so the
    // drawn box centers on (posX, posY).
    var sizePx by remember { mutableStateOf(androidx.compose.ui.unit.IntSize.Zero) }
    Box(
        Modifier
            .offset {
                IntOffset(
                    (style.posX * boxW - sizePx.width / 2f).toInt(),
                    (style.posY * boxH - sizePx.height / 2f).toInt(),
                )
            }
            .width(with(density) { (boxW * 0.86f).toDp() })
            .onSizeChanged { sizePx = it }
            .then(
                if (style.background == CaptionBackground.BOX) {
                    Modifier.background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(6.dp))
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                } else {
                    Modifier
                },
            )
            .pointerInput(boxW, boxH) {
                detectDragGestures { change, _ ->
                    change.consume()
                    val cx = (style.posX * boxW + change.positionChange().x).coerceIn(boxW * 0.05f, boxW * 0.95f)
                    val cy = (style.posY * boxH + change.positionChange().y).coerceIn(boxH * 0.03f, boxH * 0.97f)
                    onMove(cx / boxW, cy / boxH)
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            color = color,
            fontFamily = fontFamily,
            fontWeight = FontWeight.Bold,
            fontSize = fontSizeSp,
            textAlign = TextAlign.Center,
            maxLines = 3,
            style = if (style.background == CaptionBackground.SHADOW) {
                MaterialTheme.typography.bodyLarge.copy(
                    shadow = androidx.compose.ui.graphics.Shadow(
                        color = Color.Black.copy(alpha = 0.9f),
                        offset = Offset(0f, 2f),
                        blurRadius = with(density) { (fontSizeSp.toPx() * 0.14f) },
                    ),
                )
            } else {
                MaterialTheme.typography.bodyLarge
            },
        )
    }
}

@Composable
private fun ResultPhase(
    resultFile: File?,
    aspect: ClipAspect,
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

// MARK: small helpers

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
private fun saveToGallery(context: Context, file: File): Boolean {
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
private fun shareClip(context: Context, file: File) {
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
