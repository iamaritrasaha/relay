package org.localsend.localsend_app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import java.io.File
import java.security.KeyStore
import java.security.KeyStoreException
import java.security.NoSuchAlgorithmException
import java.security.ProviderException
import java.security.UnrecoverableKeyException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private const val RELAY_IDENTITY_KEY_ALIAS = "org.localsend.localsend_app.relay_identity_secret_v1"
private const val RELAY_IDENTITY_SECRET_FILE = "relay_identity_secret_v1"
private const val AES_TRANSFORMATION = "AES/GCM/NoPadding"
private const val GCM_TAG_LENGTH_BITS = 128

/** Stores Relay's PKCS#8 private-key bytes encrypted with an Android Keystore key. */
class RelayIdentitySecretStore(private val context: Context) {
    fun load(): RelayIdentitySecretLoadResult {
        val file = secretFile()
        if (!file.exists()) {
            return RelayIdentitySecretLoadResult.NotFound
        }

        return try {
            val blob = RelayIdentitySecretBlob.decode(file.readBytes()) ?: return RelayIdentitySecretLoadResult.Corrupt
            val key = getExistingKey() ?: return RelayIdentitySecretLoadResult.Corrupt
            val cipher = Cipher.getInstance(AES_TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_LENGTH_BITS, blob.iv))
            RelayIdentitySecretLoadResult.Found(cipher.doFinal(blob.ciphertext))
        } catch (error: Exception) {
            error.toLoadResult()
        }
    }

    fun save(secret: ByteArray): RelayIdentitySecretStoreResult {
        return try {
            val cipher = Cipher.getInstance(AES_TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
            val blob = RelayIdentitySecretBlob(cipher.iv, cipher.doFinal(secret)).encode()
            val directory = context.noBackupFilesDir
            if (!directory.exists() && !directory.mkdirs()) {
                return RelayIdentitySecretStoreResult.Failed
            }
            secretFile().outputStream().use { it.write(blob) }
            RelayIdentitySecretStoreResult.Success
        } catch (error: Exception) {
            error.toStoreResult()
        }
    }

    /** Deletes both the encrypted secret and its Keystore wrapping key. */
    fun delete(): RelayIdentitySecretStoreResult {
        return try {
            val file = secretFile()
            if (file.exists() && !file.delete()) {
                return RelayIdentitySecretStoreResult.Failed
            }
            val keyStore = keyStore()
            if (keyStore.containsAlias(RELAY_IDENTITY_KEY_ALIAS)) {
                keyStore.deleteEntry(RELAY_IDENTITY_KEY_ALIAS)
            }
            RelayIdentitySecretStoreResult.Success
        } catch (error: Exception) {
            error.toStoreResult()
        }
    }

    private fun secretFile(): File = File(context.noBackupFilesDir, RELAY_IDENTITY_SECRET_FILE)

    private fun getExistingKey(): SecretKey? = keyStore().getKey(RELAY_IDENTITY_KEY_ALIAS, null) as? SecretKey

    private fun getOrCreateKey(): SecretKey {
        getExistingKey()?.let { return it }

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                RELAY_IDENTITY_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return keyGenerator.generateKey()
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
}

sealed interface RelayIdentitySecretLoadResult {
    data class Found(val secret: ByteArray) : RelayIdentitySecretLoadResult
    data object NotFound : RelayIdentitySecretLoadResult
    data object Locked : RelayIdentitySecretLoadResult
    data object NotAvailable : RelayIdentitySecretLoadResult
    data object PermissionDenied : RelayIdentitySecretLoadResult
    data object Corrupt : RelayIdentitySecretLoadResult
    data object Failed : RelayIdentitySecretLoadResult
}

sealed interface RelayIdentitySecretStoreResult {
    data object Success : RelayIdentitySecretStoreResult
    data object Locked : RelayIdentitySecretStoreResult
    data object NotAvailable : RelayIdentitySecretStoreResult
    data object PermissionDenied : RelayIdentitySecretStoreResult
    data object Failed : RelayIdentitySecretStoreResult
}

private fun Exception.toLoadResult(): RelayIdentitySecretLoadResult = when (this) {
    is UserNotAuthenticatedException -> RelayIdentitySecretLoadResult.Locked
    is KeyPermanentlyInvalidatedException, is UnrecoverableKeyException, is AEADBadTagException -> RelayIdentitySecretLoadResult.Corrupt
    is KeyStoreException, is NoSuchAlgorithmException, is ProviderException -> RelayIdentitySecretLoadResult.NotAvailable
    is SecurityException -> RelayIdentitySecretLoadResult.PermissionDenied
    else -> RelayIdentitySecretLoadResult.Failed
}

private fun Exception.toStoreResult(): RelayIdentitySecretStoreResult = when (this) {
    is UserNotAuthenticatedException -> RelayIdentitySecretStoreResult.Locked
    is KeyStoreException, is NoSuchAlgorithmException, is ProviderException -> RelayIdentitySecretStoreResult.NotAvailable
    is SecurityException -> RelayIdentitySecretStoreResult.PermissionDenied
    else -> RelayIdentitySecretStoreResult.Failed
}

/** Versioned binary format: magic (4 bytes), version (1), IV length (1), IV, ciphertext plus GCM tag. */
private data class RelayIdentitySecretBlob(val iv: ByteArray, val ciphertext: ByteArray) {
    fun encode(): ByteArray {
        val result = ByteArray(6 + iv.size + ciphertext.size)
        result[0] = 'R'.code.toByte()
        result[1] = 'L'.code.toByte()
        result[2] = 'Y'.code.toByte()
        result[3] = '1'.code.toByte()
        result[4] = VERSION
        result[5] = iv.size.toByte()
        iv.copyInto(result, destinationOffset = 6)
        ciphertext.copyInto(result, destinationOffset = 6 + iv.size)
        return result
    }

    companion object {
        private const val VERSION: Byte = 1
        private const val GCM_IV_LENGTH = 12
        private const val GCM_TAG_LENGTH_BYTES = 16

        fun decode(bytes: ByteArray): RelayIdentitySecretBlob? {
            if (bytes.size < 6 + GCM_IV_LENGTH + GCM_TAG_LENGTH_BYTES) return null
            if (bytes[0] != 'R'.code.toByte() || bytes[1] != 'L'.code.toByte() || bytes[2] != 'Y'.code.toByte() || bytes[3] != '1'.code.toByte()) return null
            if (bytes[4] != VERSION) return null

            val ivLength = bytes[5].toInt() and 0xff
            if (ivLength != GCM_IV_LENGTH || bytes.size < 6 + ivLength + GCM_TAG_LENGTH_BYTES) return null

            return RelayIdentitySecretBlob(
                iv = bytes.copyOfRange(6, 6 + ivLength),
                ciphertext = bytes.copyOfRange(6 + ivLength, bytes.size),
            )
        }
    }
}
