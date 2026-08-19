package org.localsend.localsend_app.continuity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Continuity's platform-facing behaviour, exercised through the narrow
 * interfaces with fakes. Nothing here touches an Android API, so it runs on a
 * plain JVM without a device.
 */
class ContinuityContractsTest {

    // ------------------------------------------------------------- battery

    @Test
    fun `a first battery reading is always worth publishing`() {
        val snapshot = BatterySnapshot(percentage = 82, charging = ChargingState.CHARGING)
        assertTrue(snapshot.isMeaningfullyDifferentFrom(null))
    }

    @Test
    fun `an identical battery reading is not republished`() {
        val snapshot = BatterySnapshot(percentage = 82, charging = ChargingState.DISCHARGING)
        val same = BatterySnapshot(percentage = 82, charging = ChargingState.DISCHARGING)
        assertFalse(
            "republishing an unchanged reading would wake both radios for nothing",
            snapshot.isMeaningfullyDifferentFrom(same),
        )
    }

    @Test
    fun `plugging in is published even at the same level`() {
        val discharging = BatterySnapshot(percentage = 82, charging = ChargingState.DISCHARGING)
        val charging = BatterySnapshot(percentage = 82, charging = ChargingState.CHARGING)
        assertTrue(charging.isMeaningfullyDifferentFrom(discharging))
    }

    @Test
    fun `an unknown level is never smoothed into a number`() {
        val unknown = BatterySnapshot(percentage = null, charging = ChargingState.UNKNOWN)
        assertEquals(null, unknown.percentage)
        // Going from unknown to known, and back, are both real changes.
        val known = BatterySnapshot(percentage = 50, charging = ChargingState.UNKNOWN)
        assertTrue(known.isMeaningfullyDifferentFrom(unknown))
        assertTrue(unknown.isMeaningfullyDifferentFrom(known))
    }

    // --------------------------------------------------------- capabilities

    @Test
    fun `a capability state carries its reason to the UI`() {
        val limited = CapabilityState.Limited("Android only lets the focused app read the clipboard.")
        val encoded = limited.encode()
        assertEquals("limited", encoded["state"])
        assertEquals("Android only lets the focused app read the clipboard.", encoded["reason"])
    }

    @Test
    fun `an available capability has nothing to explain`() {
        assertEquals(mapOf("state" to "available"), CapabilityState.Available.encode())
    }

    @Test
    fun `a permission-required capability is distinguishable from an unavailable one`() {
        assertEquals("permissionRequired", CapabilityState.PermissionRequired("grant it").encode()["state"])
        assertEquals("unavailable", CapabilityState.Unavailable("no telephony").encode()["state"])
    }

    // ----------------------------------------------------------- clipboard

    @Test
    fun `a clipboard the app may not read reports why rather than looking empty`() {
        val provider = FakeClipboardProvider(readable = false)
        val result = provider.read()
        assertTrue(result is ClipboardReadResult.RequiresForeground)
        assertTrue((result as ClipboardReadResult.RequiresForeground).reason.isNotBlank())
    }

    @Test
    fun `writing the clipboard works even when reading it does not`() {
        // This asymmetry is the whole reason desktop to phone sharing is fully
        // available while phone to desktop is limited.
        val provider = FakeClipboardProvider(readable = false)
        assertTrue(provider.write("from the desktop"))
        assertEquals("from the desktop", provider.written)
    }

    // ------------------------------------------------------------ messages

    @Test
    fun `message pages stay bounded`() {
        val provider = FakeSmsProvider(total = 500)
        val page = provider.messages("42", limit = 25, beforeMs = null)
        assertEquals(25, page.items.size)
        assertTrue("an unfetched remainder must be reported", page.hasMore)
    }

    @Test
    fun `the last page reports that there is nothing older`() {
        val provider = FakeSmsProvider(total = 10)
        val page = provider.messages("42", limit = 25, beforeMs = null)
        assertEquals(10, page.items.size)
        assertFalse(page.hasMore)
    }

    @Test
    fun `sending without permission is rejected with a reason, not silently dropped`() {
        val provider = FakeSmsProvider(total = 0, canSend = false)
        val result = provider.send(listOf("+10000000000"), "hello")
        assertTrue(result is SmsSendResult.Rejected)
        assertTrue((result as SmsSendResult.Rejected).reason.isNotBlank())
    }

    // --------------------------------------------------------------- calls

    @Test
    fun `an action the platform cannot perform is unsupported, never a silent success`() {
        val provider = FakeTelephonyProvider(canAnswer = false)
        val result = provider.perform(CallAction.ANSWER, null)
        assertTrue(result is CallActionResult.Unsupported)
        assertTrue((result as CallActionResult.Unsupported).reason.isNotBlank())
    }

    @Test
    fun `a caller with no exposed number gets no invented name`() {
        val provider = FakeTelephonyProvider(canAnswer = true, address = null)
        val snapshot = provider.snapshot()
        assertEquals(null, snapshot.address)
        assertEquals(null, snapshot.displayName)
    }

    @Test
    fun `a resolved contact name comes from the local resolver only`() {
        val contacts = FakeContactResolver(mapOf("+10000000000" to "Mum"))
        assertEquals("Mum", contacts.displayNameFor("+10000000000"))
        assertEquals(null, contacts.displayNameFor("+19999999999"))
    }
}

// ------------------------------------------------------------------ fakes

private class FakeClipboardProvider(private val readable: Boolean) : ClipboardProvider {
    var written: String? = null

    override fun read(): ClipboardReadResult = if (readable) {
        ClipboardReadResult.Text("copied")
    } else {
        ClipboardReadResult.RequiresForeground(AndroidClipboardProvider.FOREGROUND_ONLY_REASON)
    }

    override fun write(text: String): Boolean {
        written = text
        return true
    }

    override fun observe(onChange: (String) -> Unit): AutoCloseable = AutoCloseable {}
}

private class FakeSmsProvider(
    private val total: Int,
    private val canSend: Boolean = true,
) : SmsProvider {
    override fun conversations(limit: Int, beforeMs: Long?): Page<SmsConversationRow> =
        Page(emptyList(), hasMore = false)

    override fun messages(conversationId: String, limit: Int, beforeMs: Long?): Page<SmsMessageRow> {
        val bounded = limit.coerceIn(1, AndroidSmsProvider.MAX_PAGE)
        val rows = (0 until minOf(total, bounded)).map { index ->
            SmsMessageRow(
                conversationId = conversationId,
                messageId = "$index",
                outgoing = false,
                address = "+10000000000",
                body = "message $index",
                sentAtMs = index.toLong(),
                read = true,
            )
        }
        return Page(rows, hasMore = total > bounded)
    }

    override fun send(recipients: List<String>, body: String): SmsSendResult = if (canSend) {
        SmsSendResult.Sent
    } else {
        SmsSendResult.Rejected(AndroidSmsProvider.SEND_PERMISSION_REASON)
    }

    override fun observeIncoming(onMessage: (SmsMessageRow) -> Unit): AutoCloseable = AutoCloseable {}
}

private class FakeTelephonyProvider(
    private val canAnswer: Boolean,
    private val address: String? = null,
) : TelephonyProvider {
    override fun snapshot(): CallSnapshot =
        CallSnapshot(CallPhase.RINGING, address, null, null)

    override fun observe(onChange: (CallSnapshot) -> Unit): AutoCloseable = AutoCloseable {}

    override fun perform(action: CallAction, address: String?): CallActionResult = when {
        action == CallAction.ANSWER && !canAnswer ->
            CallActionResult.Unsupported(AndroidTelephonyProvider.ANSWER_PERMISSION_REASON)
        else -> CallActionResult.Accepted
    }
}

private class FakeContactResolver(private val names: Map<String, String>) : ContactResolver {
    override fun displayNameFor(address: String): String? = names[address]
}
