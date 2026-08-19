package com.foresight.app.relay.continuity

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SmsMessage

/**
 * Messages through the public Telephony content provider and SmsManager.
 *
 * Relay never becomes the default SMS handler. It reads through the documented
 * provider under READ_SMS and sends under SEND_SMS, which is everything the
 * product needs and nothing more. Requesting the default-SMS role purely to
 * unlock a nicer demo would be an inappropriate role claim.
 *
 * Retrieval is always bounded: the caller names a limit and an optional cursor,
 * and the user's whole message store is never copied to another device.
 */
class AndroidSmsProvider(
    private val context: Context,
    private val contacts: ContactResolver,
) : SmsProvider {

    companion object {
        /** Matches the protocol's page cap; a larger request is clamped, not honoured. */
        const val MAX_PAGE = 100
        const val READ_PERMISSION_REASON = "Relay needs the Messages permission on this phone."
        const val SEND_PERMISSION_REASON = "Relay needs permission to send messages on this phone."
    }

    fun canRead(): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    fun canReceive(): Boolean =
        context.checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    fun canSend(): Boolean =
        context.checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED

    override fun conversations(limit: Int, beforeMs: Long?): Page<SmsConversationRow> {
        if (!canRead()) return Page(emptyList(), hasMore = false)
        val bounded = limit.coerceIn(1, MAX_PAGE)
        // One extra row tells us whether an older page exists without a count query.
        val selection = beforeMs?.let { "${Telephony.Sms.DATE} < ?" }
        val args = beforeMs?.let { arrayOf(it.toString()) }
        val rows = ArrayList<SmsConversationRow>(bounded)
        val seenThreads = HashSet<String>()

        runCatching {
            context.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                arrayOf(
                    Telephony.Sms.THREAD_ID,
                    Telephony.Sms.ADDRESS,
                    Telephony.Sms.BODY,
                    Telephony.Sms.DATE,
                    Telephony.Sms.READ,
                ),
                selection,
                args,
                "${Telephony.Sms.DATE} DESC",
            )?.use { cursor ->
                while (cursor.moveToNext() && rows.size <= bounded) {
                    val threadId = cursor.getString(0) ?: continue
                    if (!seenThreads.add(threadId)) continue
                    val address = cursor.getString(1)
                    rows.add(
                        SmsConversationRow(
                            conversationId = threadId,
                            displayName = address?.let { contacts.displayNameFor(it) },
                            addresses = listOfNotNull(address),
                            snippet = cursor.getString(2),
                            lastMessageAtMs = cursor.getLong(3),
                            unread = cursor.getInt(4) == 0,
                        ),
                    )
                }
            }
        }

        val hasMore = rows.size > bounded
        return Page(rows.take(bounded), hasMore)
    }

    override fun messages(conversationId: String, limit: Int, beforeMs: Long?): Page<SmsMessageRow> {
        if (!canRead()) return Page(emptyList(), hasMore = false)
        val bounded = limit.coerceIn(1, MAX_PAGE)
        val selection = StringBuilder("${Telephony.Sms.THREAD_ID} = ?")
        val args = ArrayList<String>()
        args.add(conversationId)
        if (beforeMs != null) {
            selection.append(" AND ${Telephony.Sms.DATE} < ?")
            args.add(beforeMs.toString())
        }

        val rows = ArrayList<SmsMessageRow>(bounded + 1)
        runCatching {
            context.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                arrayOf(
                    Telephony.Sms._ID,
                    Telephony.Sms.ADDRESS,
                    Telephony.Sms.BODY,
                    Telephony.Sms.DATE,
                    Telephony.Sms.TYPE,
                    Telephony.Sms.READ,
                ),
                selection.toString(),
                args.toTypedArray(),
                "${Telephony.Sms.DATE} DESC LIMIT ${bounded + 1}",
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    rows.add(
                        SmsMessageRow(
                            conversationId = conversationId,
                            messageId = cursor.getString(0) ?: continue,
                            address = cursor.getString(1),
                            body = cursor.getString(2).orEmpty(),
                            sentAtMs = cursor.getLong(3),
                            outgoing = cursor.getInt(4) == Telephony.Sms.MESSAGE_TYPE_SENT,
                            read = cursor.getInt(5) != 0,
                        ),
                    )
                }
            }
        }

        val hasMore = rows.size > bounded
        return Page(rows.take(bounded), hasMore)
    }

    override fun send(recipients: List<String>, body: String): SmsSendResult {
        if (!canSend()) return SmsSendResult.Rejected(SEND_PERMISSION_REASON)
        if (recipients.isEmpty()) return SmsSendResult.Rejected("No recipient was given.")
        if (body.isEmpty()) return SmsSendResult.Rejected("The message was empty.")

        val manager = runCatching {
            context.getSystemService(SmsManager::class.java)
        }.getOrNull() ?: return SmsSendResult.Failed("This device has no SMS service.")

        return runCatching {
            for (recipient in recipients) {
                // Long messages must be divided; sendTextMessage silently
                // truncates past one part on some devices.
                val parts = manager.divideMessage(body)
                if (parts.size <= 1) {
                    manager.sendTextMessage(recipient, null, body, null, null)
                } else {
                    manager.sendMultipartTextMessage(recipient, null, parts, null, null)
                }
            }
            SmsSendResult.Sent
        }.getOrElse { error ->
            SmsSendResult.Failed(error.message ?: "The message could not be sent.")
        }
    }

    override fun observeIncoming(onMessage: (SmsMessageRow) -> Unit): AutoCloseable {
        if (!canReceive()) return AutoCloseable {}
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
                val messages: Array<SmsMessage> =
                    runCatching { Telephony.Sms.Intents.getMessagesFromIntent(intent) }
                        .getOrNull() ?: return
                // Multi-part messages arrive as several PDUs of one message.
                val body = messages.joinToString(separator = "") { it.displayMessageBody.orEmpty() }
                val first = messages.firstOrNull() ?: return
                onMessage(
                    SmsMessageRow(
                        // The thread id is assigned by the provider after the
                        // message is stored; the peer resolves it on next load.
                        conversationId = first.originatingAddress.orEmpty(),
                        messageId = "${first.timestampMillis}",
                        outgoing = false,
                        address = first.originatingAddress,
                        body = body,
                        sentAtMs = first.timestampMillis,
                        read = false,
                    ),
                )
            }
        }
        context.registerReceiver(receiver, IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION))
        return AutoCloseable { runCatching { context.unregisterReceiver(receiver) } }
    }
}
