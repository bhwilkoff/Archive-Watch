package app.archivewatch.android.cast

import android.content.Context
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider

/**
 * Cast configuration — **google flavor only**.
 *
 * The Cast SDK finds this class through an `OPTIONS_PROVIDER_CLASS_NAME`
 * meta-data entry in the google-flavor manifest; it is never referenced from
 * app code, so nothing here may be renamed without editing that manifest too.
 *
 * The receiver is our own custom receiver (hosted at archivewatch.org/cast/),
 * not Google's Default Media Receiver: the custom one carries the side-loaded
 * WebVTT subtitle tracks, the public-domain provenance credit, and real error
 * text instead of a black screen.
 *
 * ⚠️ A registered receiver stays UNPUBLISHED until it is published in the Cast
 * console, and Google launches an unpublished receiver ONLY on devices added
 * under Console → Devices. Before publication, casting works on registered test
 * devices and silently does nothing elsewhere. That is Google's behaviour, not
 * a defect here (backlog C1/O1).
 */
class CastOptionsProvider : OptionsProvider {

    override fun getCastOptions(context: Context): CastOptions =
        CastOptions.Builder()
            .setReceiverApplicationId(RECEIVER_APP_ID)
            // Do not resume a stale session on launch: the app is a browser
            // first, and silently re-attaching to a TV the user finished with
            // hijacks their next play.
            .setResumeSavedSession(false)
            .setEnableReconnectionService(true)
            .setStopReceiverApplicationWhenEndingSession(true)
            .build()

    override fun getAdditionalSessionProviders(context: Context): MutableList<SessionProvider>? = null

    companion object {
        /** Archive Watch custom receiver, registered 2026-08-05. */
        const val RECEIVER_APP_ID = "58AF34C3"
    }
}
