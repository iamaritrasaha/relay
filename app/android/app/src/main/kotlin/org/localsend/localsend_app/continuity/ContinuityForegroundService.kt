package org.localsend.localsend_app.continuity

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
import org.localsend.localsend_app.MainActivity
import org.localsend.localsend_app.R

/**
 * Keeps the continuity connection alive while the app is not in the foreground.
 *
 * This service exists **only** while at least one continuity capability is
 * enabled for at least one device. A fresh install, or an install used purely
 * for LAN file transfer, never starts it, so nothing about existing transfer
 * behaviour changes.
 *
 * The declared type is `connectedDevice`, which is what Android defines for
 * interacting with a companion device, rather than `dataSync`, whose per-day
 * runtime is capped from Android 15.
 *
 * The notification is required by the platform and is deliberately quiet and
 * honest: it names what is running and offers a way to stop it.
 */
class ContinuityForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "relay_continuity"
        private const val NOTIFICATION_ID = 0x5230
        const val ACTION_STOP = "org.localsend.localsend_app.continuity.STOP"

        fun start(context: Context) {
            val intent = Intent(context, ContinuityForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ContinuityForegroundService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        startForegroundCompat()
        // The connection is owned by the Dart/Rust layer in this same process;
        // the service exists to keep that process alive, not to reconnect on
        // its own, so a restart with no intent is enough.
        return START_STICKY
    }

    private fun startForegroundCompat() {
        createChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Device continuity",
            // Low importance: this is a status, never an interruption.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shown while Relay is connected to your other devices."
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            MainActivity.createDefaultIntent(this),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, ContinuityForegroundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Relay continuity")
            .setContentText("Connected to your devices")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(null, "Turn off", stop).build(),
            )
            .build()
    }
}
