package org.localsend.localsend_app.continuity

import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract

/**
 * Resolves one number to one name, on this device, only when the user granted
 * READ_CONTACTS.
 *
 * The whole address book is never read and never leaves the phone: a lookup
 * happens per conversation, and only the resulting display name is sent. There
 * is no contact synchronisation of any kind.
 */
class ContactNameResolver(private val context: Context) : ContactResolver {

    private val cache = HashMap<String, String?>()

    private fun hasPermission(): Boolean =
        context.checkSelfPermission(android.Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED

    override fun displayNameFor(address: String): String? {
        if (address.isBlank() || !hasPermission()) return null
        cache[address]?.let { return it }
        if (cache.containsKey(address)) return null

        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(address),
        )
        val name = runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull()
        cache[address] = name
        return name
    }
}
