package app.archivewatch.android.cast

import android.content.Context
import android.view.View
import androidx.mediarouter.app.MediaRouteButton
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaTrack
import com.google.android.gms.cast.framework.CastButtonFactory
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastState
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability

/**
 * Cast support — **google flavor**.
 *
 * The amazon-flavor twin of this file has the identical signature and returns
 * "unsupported" for everything, so call sites never branch on store
 * (docs/TV-DESIGN.md §6.6, Decision 047).
 *
 * Even here, GMS presence is checked at runtime rather than assumed: a Play
 * build can legitimately land on a device with Play Services missing, stale, or
 * disabled, and `CastContext.getSharedInstance` throws in that case. Casting is
 * a bonus route to the TV — it must never be able to take the app down.
 */
object CastSupport {

    const val IS_SUPPORTED: Boolean = true

    @Volatile
    private var context: CastContext? = null

    /**
     * Initialize lazily and defensively. Safe to call more than once, and safe
     * to call on a device with no usable Play Services.
     */
    fun initialize(appContext: Context) {
        if (context != null) return
        val gms = GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(appContext)
        if (gms != ConnectionResult.SUCCESS) return
        context = runCatching { CastContext.getSharedInstance(appContext) }.getOrNull()
    }

    /** True once a receiver device is discoverable or connected. */
    fun isCastAvailable(): Boolean {
        val state = context?.castState ?: return false
        return state != CastState.NO_DEVICES_AVAILABLE
    }

    /** True while a receiver is actually connected. */
    fun isCasting(): Boolean =
        context?.sessionManager?.currentCastSession?.isConnected == true

    /**
     * The system Cast button. Returning the real `MediaRouteButton` rather than
     * drawing our own is what gives us Google's device picker, its connection
     * states and its accessibility behaviour for free — and the Cast design
     * checklist expects that exact affordance.
     *
     * Returns null when Cast is unusable, so the caller simply shows nothing.
     */
    fun createCastButton(ctx: Context): View? {
        if (context == null) return null
        return runCatching {
            MediaRouteButton(ctx).also { CastButtonFactory.setUpMediaRouteButton(ctx, it) }
        }.getOrNull()
    }

    /**
     * Hand the current film to the receiver, continuing from [positionMs].
     *
     * [captions] must carry the PUBLISHED https urls: the receiver fetches them
     * itself. (The web sender hits the analogous trap from the other side — it
     * must not send its local `blob:` url, which is scoped to the sender's
     * document.)
     *
     * @return true if a load was issued; false when there is no session, in
     *   which case the caller just keeps playing locally.
     */
    fun loadMedia(
        url: String,
        title: String,
        description: String?,
        captions: List<CastCaption>,
        positionMs: Long,
    ): Boolean {
        val client = context?.sessionManager?.currentCastSession?.remoteMediaClient ?: return false
        return runCatching {
            val meta = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE).apply {
                putString(MediaMetadata.KEY_TITLE, title)
                description?.takeIf { it.isNotBlank() }
                    ?.let { putString(MediaMetadata.KEY_SUBTITLE, it) }
            }
            val tracks = captions.mapIndexed { i, c ->
                MediaTrack.Builder((i + 1).toLong(), MediaTrack.TYPE_TEXT)
                    .setSubtype(MediaTrack.SUBTYPE_SUBTITLES)
                    .setContentId(c.url)
                    .setContentType("text/vtt")
                    .setName(c.label)
                    .setLanguage(c.lang)
                    .build()
            }
            val info = MediaInfo.Builder(url)
                .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
                .setContentType("video/mp4")
                .setMetadata(meta)
                .apply { if (tracks.isNotEmpty()) setMediaTracks(tracks) }
                .build()
            client.load(
                MediaLoadRequestData.Builder()
                    .setMediaInfo(info)
                    .setAutoplay(true)
                    .setCurrentTime(positionMs)
                    .build()
            )
            true
        }.getOrDefault(false)
    }
}
