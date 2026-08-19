package com.foresight.app.relay.continuity

import android.app.Notification
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Mirrors Android notifications through the documented listener service.
 *
 * The user grants this in Android's own "Notification access" settings screen;
 * there is no way for the app to grant it to itself, and Relay does not try.
 *
 * Only fields a person would read on the other device are forwarded: the app
 * name, title, body, timestamp and a stable key. Raw extras bundles, remote
 * views, custom parcelables and binary assets are never transported.
 */
class RelayNotificationListenerService : NotificationListenerService() {

    companion object {
        /** Set by the plugin so posted notifications reach the continuity layer. */
        @Volatile
        var sink: NotificationSink? = null

        @Volatile
        var connected: Boolean = false

        /**
         * The live service, when Android has bound it.
         *
         * Dismissing a notification has to go through the bound service; there
         * is no static API for it.
         */
        @Volatile
        var instance: RelayNotificationListenerService? = null

        const val PERMISSION_REASON =
            "Turn on notification access for Relay in Android settings."

        /** Whether the user has granted notification access to this package. */
        fun isEnabled(context: Context): Boolean {
            val enabled = runCatching {
                Settings.Secure.getString(
                    context.contentResolver,
                    "enabled_notification_listeners",
                )
            }.getOrNull().orEmpty()
            return enabled.split(':').any { entry ->
                entry.substringBefore('/') == context.packageName
            }
        }

        fun settingsIntent(): Intent =
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    interface NotificationSink {
        fun onPosted(
            key: String,
            appLabel: String,
            title: String?,
            body: String?,
            postedAtMs: Long,
            clearable: Boolean,
        )

        fun onRemoved(key: String)
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        connected = true
        instance = this
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        connected = false
        instance = null
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn ?: return
        val sink = sink ?: return
        if (shouldSkip(notification)) return

        val extras = notification.notification.extras
        val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val body = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()

        sink.onPosted(
            key = notification.key,
            appLabel = appLabel(notification.packageName),
            title = title,
            body = body,
            postedAtMs = notification.postTime,
            clearable = notification.isClearable,
        )
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        val notification = sbn ?: return
        sink?.onRemoved(notification.key)
    }

    /**
     * Dismisses a mirrored notification at the peer's request.
     *
     * Only a key that came from this device is ever passed here, and the
     * platform simply ignores one it does not recognise.
     */
    fun dismiss(key: String) {
        runCatching { cancelNotification(key) }
    }

    private fun shouldSkip(notification: StatusBarNotification): Boolean {
        // Relay's own service notification must not be mirrored back.
        if (notification.packageName == packageName) return true
        val flags = notification.notification.flags
        // Ongoing/group-summary entries are scaffolding, not messages.
        if (flags and Notification.FLAG_GROUP_SUMMARY != 0) return true
        return flags and Notification.FLAG_ONGOING_EVENT != 0
    }

    private fun appLabel(packageName: String): String = runCatching {
        val manager = applicationContext.packageManager
        manager.getApplicationLabel(manager.getApplicationInfo(packageName, 0)).toString()
    }.getOrDefault(packageName)
}
