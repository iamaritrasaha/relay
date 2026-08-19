package org.localsend.localsend_app.continuity

/**
 * Narrow interfaces between Relay continuity and the Android platform.
 *
 * Every Android system integration sits behind one of these, so the behaviour
 * around it can be unit tested with a fake and no phone. Nothing in this file
 * touches an Android API.
 */

/** Charge state exactly as the platform reported it. `UNKNOWN` is never smoothed. */
enum class ChargingState { DISCHARGING, CHARGING, FULL, NOT_CHARGING, UNKNOWN }

data class BatterySnapshot(
    /** `null` when the platform did not report a level. Never synthesised. */
    val percentage: Int?,
    val charging: ChargingState,
) {
    /**
     * Whether this differs from [other] enough to be worth a network message.
     *
     * Battery level ticks constantly; publishing every tick would cost radio
     * wakeups on both devices for no visible change.
     */
    fun isMeaningfullyDifferentFrom(other: BatterySnapshot?): Boolean {
        if (other == null) return true
        if (charging != other.charging) return true
        val mine = percentage ?: return other.percentage != null
        val theirs = other.percentage ?: return true
        return mine != theirs
    }
}

interface BatteryProvider {
    fun snapshot(): BatterySnapshot

    /** Starts delivering changes. Returns a handle that stops them. */
    fun observe(onChange: (BatterySnapshot) -> Unit): AutoCloseable
}

/** Why the clipboard could not be read, in words the UI can show verbatim. */
sealed class ClipboardReadResult {
    data class Text(val value: String) : ClipboardReadResult()
    object Empty : ClipboardReadResult()

    /**
     * Android 10 (API 29) and higher only let the focused app or the default
     * input method read the clipboard. This is not a bug and there is no
     * legitimate way around it.
     */
    data class RequiresForeground(val reason: String) : ClipboardReadResult()
}

interface ClipboardProvider {
    fun read(): ClipboardReadResult
    fun write(text: String): Boolean

    /**
     * Observes clipboard changes. The callback only fires while the app is
     * eligible to read, which on current Android means while it is focused.
     */
    fun observe(onChange: (String) -> Unit): AutoCloseable
}

data class SmsConversationRow(
    val conversationId: String,
    val displayName: String?,
    val addresses: List<String>,
    val snippet: String?,
    val lastMessageAtMs: Long,
    val unread: Boolean,
)

data class SmsMessageRow(
    val conversationId: String,
    val messageId: String,
    val outgoing: Boolean,
    val address: String?,
    val body: String,
    val sentAtMs: Long,
    val read: Boolean,
)

data class Page<T>(val items: List<T>, val hasMore: Boolean)

sealed class SmsSendResult {
    object Sent : SmsSendResult()
    data class Rejected(val reason: String) : SmsSendResult()
    data class Failed(val reason: String) : SmsSendResult()
}

interface SmsProvider {
    /** Bounded page of conversations, newest first. The whole store is never copied. */
    fun conversations(limit: Int, beforeMs: Long?): Page<SmsConversationRow>

    fun messages(conversationId: String, limit: Int, beforeMs: Long?): Page<SmsMessageRow>

    fun send(recipients: List<String>, body: String): SmsSendResult

    fun observeIncoming(onMessage: (SmsMessageRow) -> Unit): AutoCloseable
}

enum class CallPhase { IDLE, RINGING, DIALING, ACTIVE, ENDED, UNKNOWN }

data class CallSnapshot(
    val phase: CallPhase,
    /** Only set when a granted permission actually exposed it. Never inferred. */
    val address: String?,
    val displayName: String?,
    val activeDurationMs: Long?,
)

enum class CallAction { DIAL, ANSWER, REJECT, HANG_UP }

sealed class CallActionResult {
    object Accepted : CallActionResult()

    /**
     * The action is not possible for this build or this device with ordinary
     * public APIs and the permissions the user granted. The reason is shown to
     * the user rather than being swallowed.
     */
    data class Unsupported(val reason: String) : CallActionResult()
    data class Failed(val reason: String) : CallActionResult()
}

interface TelephonyProvider {
    fun snapshot(): CallSnapshot
    fun observe(onChange: (CallSnapshot) -> Unit): AutoCloseable
    fun perform(action: CallAction, address: String?): CallActionResult
}

/** Resolves a number to a name locally. Contacts are never exported wholesale. */
interface ContactResolver {
    fun displayNameFor(address: String): String?
}

/** A capability's real state on this installation. */
sealed class CapabilityState {
    object Available : CapabilityState()
    data class PermissionRequired(val reason: String) : CapabilityState()
    data class Limited(val reason: String) : CapabilityState()
    data class Unavailable(val reason: String) : CapabilityState()

    fun encode(): Map<String, Any?> = when (this) {
        is Available -> mapOf("state" to "available")
        is PermissionRequired -> mapOf("state" to "permissionRequired", "reason" to reason)
        is Limited -> mapOf("state" to "limited", "reason" to reason)
        is Unavailable -> mapOf("state" to "unavailable", "reason" to reason)
    }
}
