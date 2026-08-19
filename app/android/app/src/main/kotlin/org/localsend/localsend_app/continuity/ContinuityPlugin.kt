package org.localsend.localsend_app.continuity

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The single Android entry point for Relay continuity.
 *
 * Everything privileged stays on this side of the channel. Dart asks for state,
 * receives events, and answers requests; it never holds an Android handle.
 *
 * Nothing here starts on its own. Observation and the foreground service begin
 * only when Dart says a capability is enabled, so an install that never touches
 * continuity behaves exactly as before.
 */
class ContinuityPlugin(
    private val context: Context,
    private val activityProvider: () -> Activity?,
    private val battery: BatteryProvider = AndroidBatteryProvider(context),
    private val clipboard: ClipboardProvider = AndroidClipboardProvider(context),
    private val contacts: ContactResolver = ContactNameResolver(context),
    private val sms: SmsProvider = AndroidSmsProvider(context, contacts),
    private val telephony: TelephonyProvider = AndroidTelephonyProvider(context, contacts),
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "org.localsend.localsend_app/continuity"
        const val EVENT_CHANNEL = "org.localsend.localsend_app/continuity_events"

        const val REQUEST_CODE_PERMISSIONS = 0x5231

        private val MESSAGES_PERMISSIONS = arrayOf(
            Manifest.permission.READ_SMS,
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.SEND_SMS,
        )
        private val PHONE_PERMISSIONS = arrayOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.CALL_PHONE,
            Manifest.permission.ANSWER_PHONE_CALLS,
            Manifest.permission.READ_CALL_LOG,
        )
        private val CONTACTS_PERMISSIONS = arrayOf(Manifest.permission.READ_CONTACTS)
    }

    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val observations = mutableListOf<AutoCloseable>()
    private var lastBattery: BatterySnapshot? = null
    private var lastClipboardText: String? = null

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    fun detach() {
        stopObserving()
        RelayNotificationListenerService.sink = null
    }

    // ------------------------------------------------------------- events

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun emit(event: Map<String, Any?>) {
        main.post { events?.success(event) }
    }

    // ------------------------------------------------------------ methods

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(capabilities())

            "requestPermissions" -> requestPermissions(call.argument<String>("capability"), result)

            "openNotificationAccessSettings" -> {
                // Notification access cannot be requested in-app; Android only
                // grants it through its own settings screen.
                runCatching {
                    context.startActivity(RelayNotificationListenerService.settingsIntent())
                }
                result.success(null)
            }

            "batterySnapshot" -> result.success(battery.snapshot().encode())

            "clipboardRead" -> result.success(
                when (val read = clipboard.read()) {
                    is ClipboardReadResult.Text -> mapOf("state" to "text", "text" to read.value)
                    is ClipboardReadResult.Empty -> mapOf("state" to "empty")
                    is ClipboardReadResult.RequiresForeground ->
                        mapOf("state" to "requiresForeground", "reason" to read.reason)
                },
            )

            "clipboardWrite" -> {
                val text = call.argument<String>("text").orEmpty()
                // Remember what we wrote so the change listener does not send it
                // straight back out again.
                lastClipboardText = text
                result.success(clipboard.write(text))
            }

            "smsConversations" -> {
                val page = sms.conversations(
                    limit = call.argument<Int>("limit") ?: 25,
                    beforeMs = call.argument<Number>("beforeMs")?.toLong(),
                )
                result.success(
                    mapOf(
                        "conversations" to page.items.map { it.encode() },
                        "hasMore" to page.hasMore,
                    ),
                )
            }

            "smsMessages" -> {
                val conversationId = call.argument<String>("conversationId")
                if (conversationId.isNullOrBlank()) {
                    result.error("invalid", "conversationId is required", null)
                    return
                }
                val page = sms.messages(
                    conversationId = conversationId,
                    limit = call.argument<Int>("limit") ?: 50,
                    beforeMs = call.argument<Number>("beforeMs")?.toLong(),
                )
                result.success(
                    mapOf(
                        "conversationId" to conversationId,
                        "messages" to page.items.map { it.encode() },
                        "hasMore" to page.hasMore,
                    ),
                )
            }

            "smsSend" -> {
                val recipients = call.argument<List<String>>("recipients").orEmpty()
                val body = call.argument<String>("body").orEmpty()
                result.success(
                    when (val outcome = sms.send(recipients, body)) {
                        is SmsSendResult.Sent -> mapOf("state" to "sent")
                        is SmsSendResult.Rejected ->
                            mapOf("state" to "rejected", "reason" to outcome.reason)
                        is SmsSendResult.Failed ->
                            mapOf("state" to "failed", "reason" to outcome.reason)
                    },
                )
            }

            "callSnapshot" -> result.success(telephony.snapshot().encode())

            "callAction" -> {
                val action = when (call.argument<String>("action")) {
                    "dial" -> CallAction.DIAL
                    "answer" -> CallAction.ANSWER
                    "reject" -> CallAction.REJECT
                    "hangUp" -> CallAction.HANG_UP
                    else -> null
                }
                if (action == null) {
                    result.error("invalid", "unknown call action", null)
                    return
                }
                result.success(
                    when (val outcome = telephony.perform(action, call.argument<String>("address"))) {
                        is CallActionResult.Accepted -> mapOf("state" to "accepted")
                        is CallActionResult.Unsupported ->
                            mapOf("state" to "unsupported", "reason" to outcome.reason)
                        is CallActionResult.Failed ->
                            mapOf("state" to "failed", "reason" to outcome.reason)
                    },
                )
            }

            "dismissNotification" -> {
                val key = call.argument<String>("key")
                if (!key.isNullOrBlank()) {
                    RelayNotificationListenerService.instance?.dismiss(key)
                }
                result.success(null)
            }

            "startObserving" -> {
                startObserving(call.argument<List<String>>("capabilities").orEmpty().toSet())
                result.success(null)
            }

            "stopObserving" -> {
                stopObserving()
                result.success(null)
            }

            "startBackgroundService" -> {
                ContinuityForegroundService.start(context)
                result.success(null)
            }

            "stopBackgroundService" -> {
                ContinuityForegroundService.stop(context)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------- capabilities

    /**
     * The honest state of every capability on this installation.
     *
     * These come from real permission checks and real platform version checks;
     * nothing is optimistic.
     */
    fun capabilities(): Map<String, Map<String, Any?>> {
        val smsProvider = sms as? AndroidSmsProvider
        val telephonyProvider = telephony as? AndroidTelephonyProvider

        val messages = when {
            smsProvider == null -> CapabilityState.Unavailable("Messages are not available on this device.")
            smsProvider.canRead() && smsProvider.canSend() -> CapabilityState.Available
            smsProvider.canRead() ->
                CapabilityState.Limited("Relay can show messages but not send them without the send permission.")
            else -> CapabilityState.PermissionRequired(AndroidSmsProvider.READ_PERMISSION_REASON)
        }

        val phone = when {
            telephonyProvider == null ->
                CapabilityState.Unavailable("This device has no telephony service.")
            !telephonyProvider.canReadState() ->
                CapabilityState.PermissionRequired("Relay needs the Phone permission to show call status.")
            telephonyProvider.canAnswer() && telephonyProvider.canDial() ->
                // Everything the platform allows is granted; call audio still
                // cannot leave the phone and the UI says so.
                CapabilityState.Limited(AndroidTelephonyProvider.CALL_AUDIO_LIMITATION)
            else ->
                CapabilityState.Limited(
                    "Relay can show call status. " + AndroidTelephonyProvider.ANSWER_PERMISSION_REASON,
                )
        }

        val notifications = if (RelayNotificationListenerService.isEnabled(context)) {
            CapabilityState.Available
        } else {
            CapabilityState.PermissionRequired(RelayNotificationListenerService.PERMISSION_REASON)
        }

        return mapOf(
            "battery" to CapabilityState.Available.encode(),
            // Reading is foreground-only on Android 10 and higher; writing works
            // either way, so the capability is real but limited.
            "clipboard" to CapabilityState.Limited(
                AndroidClipboardProvider.FOREGROUND_ONLY_REASON,
            ).encode(),
            "notifications" to notifications.encode(),
            "messages" to messages.encode(),
            "phone" to phone.encode(),
        )
    }

    private fun requestPermissions(capability: String?, result: MethodChannel.Result) {
        val permissions = when (capability) {
            "messages" -> MESSAGES_PERMISSIONS + CONTACTS_PERMISSIONS
            "phone" -> PHONE_PERMISSIONS + CONTACTS_PERMISSIONS
            "notifications" -> {
                // Not a runtime permission: it lives in Android's settings.
                runCatching {
                    context.startActivity(RelayNotificationListenerService.settingsIntent())
                }
                result.success(false)
                return
            }
            else -> {
                result.success(true)
                return
            }
        }
        val activity = activityProvider()
        if (activity == null) {
            result.success(false)
            return
        }
        val missing = permissions.filter {
            activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        activity.requestPermissions(missing.toTypedArray(), REQUEST_CODE_PERMISSIONS)
    }

    /** Forwarded from the activity so a request can complete. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE_PERMISSIONS) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        return true
    }

    // -------------------------------------------------------- observation

    private fun startObserving(capabilities: Set<String>) {
        stopObserving()

        if (capabilities.contains("battery")) {
            lastBattery = battery.snapshot()
            emit(mapOf("event" to "battery") + battery.snapshot().encode())
            observations += battery.observe { snapshot ->
                // Only publish a change a person would notice, so a slowly
                // draining battery does not wake the radio every percent tick.
                if (snapshot.isMeaningfullyDifferentFrom(lastBattery)) {
                    lastBattery = snapshot
                    emit(mapOf("event" to "battery") + snapshot.encode())
                }
            }
        }

        if (capabilities.contains("clipboard")) {
            observations += clipboard.observe { text ->
                // Do not re-share what a peer just gave us.
                if (text != lastClipboardText) {
                    lastClipboardText = text
                    emit(mapOf("event" to "clipboard", "text" to text))
                }
            }
        }

        if (capabilities.contains("notifications")) {
            val sink = object : RelayNotificationListenerService.NotificationSink {
                override fun onPosted(
                    key: String,
                    appLabel: String,
                    title: String?,
                    body: String?,
                    postedAtMs: Long,
                    clearable: Boolean,
                ) {
                    emit(
                        mapOf(
                            "event" to "notificationPosted",
                            "key" to key,
                            "appLabel" to appLabel,
                            "title" to title,
                            "body" to body,
                            "postedAtMs" to postedAtMs,
                            "clearable" to clearable,
                        ),
                    )
                }

                override fun onRemoved(key: String) {
                    emit(mapOf("event" to "notificationRemoved", "key" to key))
                }
            }
            RelayNotificationListenerService.sink = sink
            observations += AutoCloseable { RelayNotificationListenerService.sink = null }
        }

        if (capabilities.contains("phone")) {
            observations += telephony.observe { snapshot ->
                emit(mapOf("event" to "callState") + snapshot.encode())
            }
        }

        if (capabilities.contains("messages")) {
            observations += sms.observeIncoming { message ->
                emit(mapOf("event" to "smsReceived") + message.encode())
            }
        }
    }

    private fun stopObserving() {
        for (observation in observations) {
            runCatching { observation.close() }
        }
        observations.clear()
    }
}

// ------------------------------------------------------------- encoding

private fun BatterySnapshot.encode(): Map<String, Any?> = mapOf(
    "percentage" to percentage,
    "charging" to charging.name.lowercase(),
)

private fun CallSnapshot.encode(): Map<String, Any?> = mapOf(
    "phase" to phase.name.lowercase(),
    "address" to address,
    "displayName" to displayName,
    "activeDurationMs" to activeDurationMs,
)

private fun SmsConversationRow.encode(): Map<String, Any?> = mapOf(
    "conversationId" to conversationId,
    "displayName" to displayName,
    "addresses" to addresses,
    "snippet" to snippet,
    "lastMessageAtMs" to lastMessageAtMs,
    "unread" to unread,
)

private fun SmsMessageRow.encode(): Map<String, Any?> = mapOf(
    "conversationId" to conversationId,
    "messageId" to messageId,
    "outgoing" to outgoing,
    "address" to address,
    "body" to body,
    "sentAtMs" to sentAtMs,
    "read" to read,
)
