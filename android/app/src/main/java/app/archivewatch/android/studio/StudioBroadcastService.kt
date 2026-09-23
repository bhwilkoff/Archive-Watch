package app.archivewatch.android.studio

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import app.archivewatch.android.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * A LIVE SHOW IS A FOREGROUND SERVICE (ANDROID-DESIGN §9.7; launch audit A15).
 *
 * Without one, a host who locked the phone or switched to the Twitch app to
 * read chat lost the camera at once, the microphone on Android 11+, and could
 * lose the process mid-show. A `camera|microphone` foreground service is the
 * platform's own statement that this app is using both on purpose, and its
 * ongoing notification is where the host can always end the show.
 *
 * Declared only in the google flavour's manifest, beside CAMERA and
 * RECORD_AUDIO; the amazon flavour (Fire TV) has neither and never starts it.
 */
class StudioBroadcastService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_END) {
            CoroutineScope(Dispatchers.Main).launch { StudioController.end() }
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Live broadcast", NotificationManager.IMPORTANCE_LOW))
        val end = PendingIntent.getService(
            this, 1, Intent(this, StudioBroadcastService::class.java).setAction(ACTION_END),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val n = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_live)
            .setContentTitle("You're live")
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "End the broadcast", end).build())
            .build()
        // ONLY the types whose permission is granted: Android 14 refuses to
        // start a camera-type service without CAMERA, and throws.
        var types = 0
        if (granted(Manifest.permission.CAMERA)) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        if (granted(Manifest.permission.RECORD_AUDIO)) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && types != 0) {
                startForeground(NOTIFICATION_ID, n, types)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
            Log.i(TAG, "AWFGS started types=$types")
        } catch (e: Exception) {
            // Said, not swallowed: the show goes on in the foreground; only
            // backgrounding it is at risk.
            Log.w(TAG, "AWFGS could not start: $e")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun granted(p: String) =
        checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    private fun stopForegroundCompat() {
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    companion object {
        private const val TAG = "StudioFGS"
        private const val CHANNEL = "studio_live"
        private const val NOTIFICATION_ID = 7301
        private const val ACTION_END = "app.archivewatch.android.studio.END"

        fun start(context: Context) {
            try {
                context.startForegroundService(Intent(context, StudioBroadcastService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "AWFGS start refused: $e")
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, StudioBroadcastService::class.java))
            Log.i(TAG, "AWFGS stopped")
        }
    }
}
