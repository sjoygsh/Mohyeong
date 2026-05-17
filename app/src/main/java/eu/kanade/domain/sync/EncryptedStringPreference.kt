package eu.kanade.domain.sync

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import tachiyomi.core.common.preference.Preference

/**
 * Wraps an underlying [Preference] so its on-disk value is encrypted via
 * [SyncCrypto]. Reads return plaintext (with legacy non-marker values passed
 * through unchanged); writes always encrypt before persisting.
 */
internal class EncryptedStringPreference(
    private val delegate: Preference<String>,
) : Preference<String> {

    override fun key(): String = delegate.key()

    override fun defaultValue(): String = delegate.defaultValue()

    override fun isSet(): Boolean = delegate.isSet()

    override fun delete() = delegate.delete()

    override fun get(): String = SyncCrypto.decrypt(delegate.get())

    override fun set(value: String) {
        delegate.set(if (value.isEmpty()) value else SyncCrypto.encrypt(value))
    }

    override fun changes(): Flow<String> = delegate.changes().map { SyncCrypto.decrypt(it) }

    override fun stateIn(scope: CoroutineScope): StateFlow<String> =
        changes().stateIn(scope, SharingStarted.Eagerly, get())
}
