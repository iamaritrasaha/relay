package com.foresight.app.relay.continuity

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import java.util.concurrent.Executors

/**
 * Call state and call control through ordinary public APIs only.
 *
 * What is used, and what each needs:
 *
 *  * call state: [TelephonyManager] callbacks under READ_PHONE_STATE.
 *  * the other party's number: only available with READ_CALL_LOG from Android
 *    10 (API 29). Without it the number is genuinely not exposed, and Relay
 *    reports it as unknown rather than inventing one.
 *  * placing a call: [TelecomManager.placeCall] under CALL_PHONE.
 *  * answering: [TelecomManager.acceptRingingCall] under ANSWER_PHONE_CALLS
 *    (API 26+).
 *  * rejecting and hanging up: [TelecomManager.endCall] under ANSWER_PHONE_CALLS
 *    (API 28+).
 *
 * There is no reflection into private telephony services, no hidden API, no
 * AccessibilityService, and no root. Where an action is genuinely unavailable it
 * returns [CallActionResult.Unsupported] with the real reason.
 *
 * Routing live cellular call audio to a computer is **not** implemented and
 * cannot be: capturing the voice-call audio stream requires CAPTURE_AUDIO_OUTPUT,
 * which is a signature|privileged permission granted only to system apps.
 */
class AndroidTelephonyProvider(
    private val context: Context,
    private val contacts: ContactResolver,
) : TelephonyProvider {

    companion object {
        const val CALL_AUDIO_LIMITATION: String =
            "Call audio stays on the phone. Android only allows capturing call audio " +
                "with a system-only permission (CAPTURE_AUDIO_OUTPUT), so no app " +
                "distributed normally can route a call to a computer."
        const val ANSWER_PERMISSION_REASON =
            "Relay needs the Phone permission to answer or end calls on this phone."
        const val DIAL_PERMISSION_REASON =
            "Relay needs the Phone permission to place calls from this phone."
        const val NUMBER_UNAVAILABLE_REASON =
            "Android does not expose the caller's number without the call log permission."
    }

    private val telephony: TelephonyManager?
        get() = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager

    private val telecom: TelecomManager?
        get() = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager

    private var activeSince: Long? = null
    private var lastAddress: String? = null

    fun canReadState(): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED

    fun canReadCallLog(): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_CALL_LOG) ==
            PackageManager.PERMISSION_GRANTED

    fun canAnswer(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            context.checkSelfPermission(Manifest.permission.ANSWER_PHONE_CALLS) ==
            PackageManager.PERMISSION_GRANTED

    fun canEndCall(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && canAnswer()

    fun canDial(): Boolean =
        context.checkSelfPermission(Manifest.permission.CALL_PHONE) ==
            PackageManager.PERMISSION_GRANTED

    override fun snapshot(): CallSnapshot {
        if (!canReadState()) {
            return CallSnapshot(CallPhase.UNKNOWN, null, null, null)
        }
        val state = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telephony?.callStateForSubscription
            } else {
                @Suppress("DEPRECATION")
                telephony?.callState
            }
        }.getOrNull() ?: TelephonyManager.CALL_STATE_IDLE
        return buildSnapshot(state, lastAddress)
    }

    private fun buildSnapshot(state: Int, address: String?): CallSnapshot {
        val phase = when (state) {
            TelephonyManager.CALL_STATE_RINGING -> CallPhase.RINGING
            TelephonyManager.CALL_STATE_OFFHOOK -> CallPhase.ACTIVE
            TelephonyManager.CALL_STATE_IDLE -> CallPhase.IDLE
            else -> CallPhase.UNKNOWN
        }
        val now = System.currentTimeMillis()
        activeSince = when (phase) {
            CallPhase.ACTIVE -> activeSince ?: now
            else -> null
        }
        // Only report a number the platform actually handed us.
        val reported = address?.takeIf { it.isNotBlank() && canReadCallLog() }
        return CallSnapshot(
            phase = phase,
            address = reported,
            displayName = reported?.let { contacts.displayNameFor(it) },
            activeDurationMs = activeSince?.let { now - it },
        )
    }

    override fun observe(onChange: (CallSnapshot) -> Unit): AutoCloseable {
        val telephony = telephony ?: return AutoCloseable {}
        if (!canReadState()) return AutoCloseable {}

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val executor = Executors.newSingleThreadExecutor()
            val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    onChange(buildSnapshot(state, lastAddress))
                }
            }
            runCatching { telephony.registerTelephonyCallback(executor, callback) }
            return AutoCloseable {
                runCatching { telephony.unregisterTelephonyCallback(callback) }
                executor.shutdown()
            }
        }

        @Suppress("DEPRECATION")
        val listener = object : PhoneStateListener() {
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                // Before API 29 the number arrives here; from API 29 it is null
                // unless the app holds READ_CALL_LOG.
                if (!phoneNumber.isNullOrBlank()) lastAddress = phoneNumber
                onChange(buildSnapshot(state, lastAddress))
            }
        }
        @Suppress("DEPRECATION")
        runCatching { telephony.listen(listener, PhoneStateListener.LISTEN_CALL_STATE) }
        return AutoCloseable {
            @Suppress("DEPRECATION")
            runCatching { telephony.listen(listener, PhoneStateListener.LISTEN_NONE) }
        }
    }

    override fun perform(action: CallAction, address: String?): CallActionResult = when (action) {
        CallAction.DIAL -> dial(address)
        CallAction.ANSWER -> answer()
        CallAction.REJECT, CallAction.HANG_UP -> endCall()
    }

    private fun dial(address: String?): CallActionResult {
        if (address.isNullOrBlank()) return CallActionResult.Failed("No number was given.")
        // Only a dial string is ever accepted from the wire, and it is handed to
        // the platform's own call intent. No arbitrary intent is constructed
        // from remote data.
        if (!isPlausibleDialString(address)) {
            return CallActionResult.Failed("That is not a valid phone number.")
        }
        if (!canDial()) return CallActionResult.Unsupported(DIAL_PERMISSION_REASON)
        val uri = Uri.fromParts("tel", address, null)
        return runCatching {
            val telecom = telecom
            if (telecom != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                telecom.placeCall(uri, null)
            } else {
                context.startActivity(
                    Intent(Intent.ACTION_CALL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }
            CallActionResult.Accepted
        }.getOrElse { error ->
            CallActionResult.Failed(error.message ?: "The call could not be placed.")
        }
    }

    private fun answer(): CallActionResult {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return CallActionResult.Unsupported("This Android version cannot answer calls for an app.")
        }
        if (!canAnswer()) return CallActionResult.Unsupported(ANSWER_PERMISSION_REASON)
        val telecom = telecom ?: return CallActionResult.Failed("This device has no telephony service.")
        return runCatching {
            telecom.acceptRingingCall()
            CallActionResult.Accepted
        }.getOrElse { error ->
            CallActionResult.Failed(error.message ?: "The call could not be answered.")
        }
    }

    private fun endCall(): CallActionResult {
        if (!canEndCall()) {
            return CallActionResult.Unsupported(
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                    "This Android version does not let an app end calls."
                } else {
                    ANSWER_PERMISSION_REASON
                },
            )
        }
        val telecom = telecom ?: return CallActionResult.Failed("This device has no telephony service.")
        return runCatching {
            @Suppress("DEPRECATION")
            val ended = telecom.endCall()
            if (ended) CallActionResult.Accepted else CallActionResult.Failed("There was no call to end.")
        }.getOrElse { error ->
            CallActionResult.Failed(error.message ?: "The call could not be ended.")
        }
    }

    /**
     * A conservative dial-string check.
     *
     * Remote input never becomes a free-form URI: anything outside digits and
     * the handful of characters a dial string legitimately contains is refused.
     */
    private fun isPlausibleDialString(address: String): Boolean {
        if (address.length !in 2..32) return false
        return address.all { it.isDigit() || it in "+*#-() " } && address.any { it.isDigit() }
    }
}
