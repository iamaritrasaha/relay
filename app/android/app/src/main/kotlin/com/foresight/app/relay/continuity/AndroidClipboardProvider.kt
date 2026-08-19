package com.foresight.app.relay.continuity

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build

/**
 * Clipboard access within what Android actually permits.
 *
 * Since Android 10 (API 29) "unless your app is the default input method editor
 * or is the app that currently has focus, your app cannot access clipboard
 * data". Relay is neither an IME nor willing to abuse an AccessibilityService,
 * so reading only works while Relay is in the foreground. That limitation is
 * reported to the UI verbatim instead of being worked around.
 *
 * Writing is not restricted the same way, so Linux to Android clipboard sharing
 * works from the continuity foreground service. On Android 13 (API 33) and
 * higher the system itself shows the user a preview of what was written.
 */
class AndroidClipboardProvider(private val context: Context) : ClipboardProvider {

    private val manager: ClipboardManager?
        get() = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager

    companion object {
        const val FOREGROUND_ONLY_REASON: String =
            "Android only lets the focused app read the clipboard, so Relay can share " +
                "this device's clipboard while Relay is open."

        /** The API level from which the read restriction applies. */
        private const val CLIPBOARD_READ_RESTRICTED_FROM = Build.VERSION_CODES.Q
    }

    private fun readRestricted(): Boolean = Build.VERSION.SDK_INT >= CLIPBOARD_READ_RESTRICTED_FROM

    override fun read(): ClipboardReadResult {
        val manager = manager ?: return ClipboardReadResult.RequiresForeground(FOREGROUND_ONLY_REASON)
        // getPrimaryClip returns null rather than throwing when the caller is
        // not eligible, which is indistinguishable from an empty clipboard on
        // its own; hasPrimaryClip separates the two.
        val clip: ClipData? = runCatching { manager.primaryClip }.getOrNull()
        if (clip == null) {
            return if (readRestricted()) {
                ClipboardReadResult.RequiresForeground(FOREGROUND_ONLY_REASON)
            } else {
                ClipboardReadResult.Empty
            }
        }
        if (clip.itemCount == 0) return ClipboardReadResult.Empty
        val text = clip.getItemAt(0).coerceToText(context)?.toString().orEmpty()
        // Only text is supported. Arbitrary clipboard payloads are never
        // transported or executed.
        return if (text.isEmpty()) ClipboardReadResult.Empty else ClipboardReadResult.Text(text)
    }

    override fun write(text: String): Boolean {
        val manager = manager ?: return false
        return runCatching {
            manager.setPrimaryClip(ClipData.newPlainText("Relay", text))
            true
        }.getOrDefault(false)
    }

    override fun observe(onChange: (String) -> Unit): AutoCloseable {
        val manager = manager ?: return AutoCloseable {}
        val listener = ClipboardManager.OnPrimaryClipChangedListener {
            when (val result = read()) {
                is ClipboardReadResult.Text -> onChange(result.value)
                // Nothing to share, and nothing to complain about: the listener
                // simply does not fire usefully while backgrounded.
                is ClipboardReadResult.Empty,
                is ClipboardReadResult.RequiresForeground -> Unit
            }
        }
        manager.addPrimaryClipChangedListener(listener)
        return AutoCloseable {
            runCatching { manager.removePrimaryClipChangedListener(listener) }
        }
    }
}
