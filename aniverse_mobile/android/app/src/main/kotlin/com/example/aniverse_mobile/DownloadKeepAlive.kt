package com.example.aniverse_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the app alive while episodes download, with the app in the background
 * or the screen off. The downloading itself happens on the Dart side
 * (lib/services/download_service.dart); this is the foreground service Android
 * needs to see -- with its notification showing what is downloading -- to
 * leave the process running.
 */
class DownloadKeepAlive : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Saving episodes for offline"
        val progress = intent?.getIntExtra(EXTRA_PROGRESS, -1) ?: -1
        val n = notification(this, text, progress)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, n)
        }
        return START_NOT_STICKY
    }

    companion object {
        private const val ID = 1909
        private const val CHANNEL = "downloads"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_PROGRESS = "progress"

        fun update(ctx: Context, active: Boolean, text: String, progress: Int) {
            val intent = Intent(ctx, DownloadKeepAlive::class.java)
            if (!active) {
                ctx.stopService(intent)
                return
            }
            intent.putExtra(EXTRA_TEXT, text).putExtra(EXTRA_PROGRESS, progress)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(intent)
                else ctx.startService(intent)
            } catch (_: Exception) {
                // Android refuses a new foreground service from the background in
                // some states; the download carries on while the app is alive anyway.
            }
        }

        private fun notification(ctx: Context, text: String, progress: Int): Notification {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm?.getNotificationChannel(CHANNEL) == null) {
                nm?.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW).apply {
                        description = "Episodes being saved for offline"
                        setShowBadge(false)
                    }
                )
            }
            val open = PendingIntent.getActivity(
                ctx, 0,
                Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(ctx, CHANNEL)
            else @Suppress("DEPRECATION") Notification.Builder(ctx)
            return b
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle("Downloading")
                .setContentText(text)
                .setProgress(100, progress.coerceIn(0, 100), progress < 0)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(open)
                .build()
        }
    }
}
