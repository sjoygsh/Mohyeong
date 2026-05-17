package eu.kanade.domain.sync

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import tachiyomi.core.common.util.system.logcat
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android Keystore-backed AES/GCM encryption for sync credentials (WebDAV
 * password, Dropbox token, Google Drive token, SyncYomi API key, WebDAV
 * username). The key never leaves the secure hardware on supported devices.
 *
 * Stored values are prefixed with [MARKER] so legacy plaintext values written
 * by Mohyeong v0.19.10 and earlier can be detected and migrated lazily.
 *
 * Failures fall back to plaintext to avoid locking users out of their sync
 * setup on devices with broken Keystore implementations.
 */
internal object SyncCrypto {

    const val MARKER = "enc1:"

    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val KEY_ALIAS = "mohyeong_sync_v1"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_SIZE = 12
    private const val TAG_BITS = 128

    private val keystore: KeyStore by lazy {
        KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
    }

    private fun getOrCreateKey(): SecretKey {
        (keystore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE_PROVIDER,
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    fun encrypt(plaintext: String): String {
        if (plaintext.isEmpty()) return plaintext
        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, getOrCreateKey())
            }
            val iv = cipher.iv
            val cipherText = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
            val combined = ByteArray(iv.size + cipherText.size).also {
                System.arraycopy(iv, 0, it, 0, iv.size)
                System.arraycopy(cipherText, 0, it, iv.size, cipherText.size)
            }
            MARKER + Base64.encodeToString(combined, Base64.NO_WRAP)
        } catch (e: Throwable) {
            logcat { "SyncCrypto encrypt failed: ${e.message}; storing plaintext" }
            plaintext
        }
    }

    fun decrypt(stored: String): String {
        if (!stored.startsWith(MARKER)) return stored
        return try {
            val combined = Base64.decode(stored.removePrefix(MARKER), Base64.NO_WRAP)
            val iv = combined.copyOfRange(0, IV_SIZE)
            val cipherText = combined.copyOfRange(IV_SIZE, combined.size)
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(TAG_BITS, iv))
            }
            cipher.doFinal(cipherText).toString(Charsets.UTF_8)
        } catch (e: Throwable) {
            logcat { "SyncCrypto decrypt failed: ${e.message}" }
            ""
        }
    }
}
