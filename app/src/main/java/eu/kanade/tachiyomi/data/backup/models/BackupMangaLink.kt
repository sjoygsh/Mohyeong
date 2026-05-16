package eu.kanade.tachiyomi.data.backup.models

import kotlinx.serialization.Serializable
import kotlinx.serialization.protobuf.ProtoNumber

@Serializable
data class BackupMangaLink(
    @ProtoNumber(1) val primarySource: Long,
    @ProtoNumber(2) val primaryUrl: String,
    @ProtoNumber(3) val linkedSource: Long,
    @ProtoNumber(4) val linkedUrl: String,
    @ProtoNumber(5) val priority: Long = 0,
)
