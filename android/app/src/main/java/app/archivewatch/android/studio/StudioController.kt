package app.archivewatch.android.studio

// Watch Together Studio's live state, shared between Detail and the player
// (ANDROID-DESIGN §9.1). The Android counterpart of the Apple side's
// `StudioSession`, and it exists for the same reason: Detail decides to go
// live, the PLAYER is where the film and the surfaces are, and the two are
// different destinations in the same nav graph.
//
// It holds ONE show, because a device produces one show at a time. Everything
// about rendering, encoding and publishing stays in `StudioEngine`.

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.util.UnstableApi
import app.archivewatch.android.data.CatalogItem
import kotlinx.coroutines.CoroutineScope

@UnstableApi
object StudioController {

    /** The film the host asked to broadcast, set before the player exists. */
    var armedFilmID: String? by mutableStateOf(null)
        private set
    var armedTitle: String by mutableStateOf("")
        private set
    var armedSubtitle: String by mutableStateOf("")
        private set
    var armedProvenance: String? by mutableStateOf(null)
        private set

    /** Why the Studio refused, for the surface that asked. */
    var refusal: String? by mutableStateOf(null)

    var isLive: Boolean by mutableStateOf(false)
        private set
    var health: StudioHealth by mutableStateOf(StudioHealth())
        private set

    // What the §9.3 bottom sheet drives.
    var showsCamera: Boolean by mutableStateOf(true)
    var panelOpen: Boolean by mutableStateOf(false)

    private var engine: StudioEngine? = null
    private var audioTap: StudioFilmAudioTap? = null

    /**
     * Detail's entry point. Applies the rights gate and either refuses with a
     * sentence the host can act on, or arms the session.
     * Returns true when the caller should open the player.
     */
    fun arm(item: CatalogItem): Boolean {
        val why = StudioRights.refusal(item.rightsBucket, item.contentType, item.year)
        if (why != null) {
            refusal = why
            return false
        }
        armedFilmID = item.archiveID
        armedTitle = item.title
        armedSubtitle = listOfNotNull(item.year?.toString(), item.director)
            .filter { it.isNotBlank() }.joinToString(" · ")
        armedProvenance = if (item.rightsBucket == "safe_pd_age" && item.year != null)
            "Public domain — published ${item.year}, before 1930" else null
        return true
    }

    fun disarm() { armedFilmID = null }

    /** The tap the player must install on its `ExoPlayer` when armed. */
    fun audioTapFor(archiveID: String): StudioFilmAudioTap? {
        if (armedFilmID != archiveID) return null
        return StudioFilmAudioTap().also { audioTap = it }
    }

    /**
     * Called by the player once it exists. A no-op unless this is the film the
     * host armed — a host who goes live on one title and then plays another
     * has not armed the second.
     */
    fun startIfArmed(scope: CoroutineScope, archiveID: String, overlayWidth: Int, overlayHeight: Int) {
        if (armedFilmID != archiveID || isLive) return
        armedFilmID = null
        val e = StudioEngine()
        e.layoutShowsCamera = showsCamera
        engine = e
        e.start(
            scope = scope,
            // No destination until a client id exists (Decision 128). The
            // engine still composites and encodes, and reports NOT SENDING
            // rather than pretending.
            destination = null,
            audioTap = audioTap,
            overlay = StudioOverlayBitmap.lowerThird(
                overlayWidth, overlayHeight, armedTitle, armedSubtitle, armedProvenance),
        )
        isLive = true
    }

    /** One health sample a second, for the §9.4 readout. */
    fun pollHealth() {
        engine?.let { health = it.health }
    }

    suspend fun end() {
        engine?.stop()
        engine = null
        audioTap = null
        isLive = false
        panelOpen = false
        health = StudioHealth()
    }
}
