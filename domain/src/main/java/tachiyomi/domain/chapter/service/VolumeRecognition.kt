package tachiyomi.domain.chapter.service

/**
 * Parses a volume number out of a chapter name. Recognises common formats:
 *  - "Vol. 3", "Vol.3", "Volume 3"
 *  - "v3", "v3.5"
 *  - "Tome 3" (French)
 *  - "Book 2"
 *  - "卷 3" / "第3卷" (CJK)
 *  - "S2" (treated as season → volume) — opt-in via [recognizeSeasonAsVolume]
 *
 * Returns null if no volume marker is present.
 */
object VolumeRecognition {

    private val VOLUME_REGEX = Regex(
        """(?:^|[\s\[(])(?:vol(?:ume)?\.?\s*|v|tome\s+|book\s+)(\d+(?:\.\d+)?)(?:\b|[\s\])])""",
        RegexOption.IGNORE_CASE,
    )

    /** CJK volume markers: 卷 (juǎn / kan / gwon) preceded or followed by a number, optionally with 第/第卷. */
    private val CJK_VOLUME_REGEX = Regex(
        """(?:第\s*(\d+(?:\.\d+)?)\s*卷|卷\s*(\d+(?:\.\d+)?))""",
    )

    private val SEASON_REGEX = Regex(
        """(?:^|[\s\[(])s(?:eason)?\s*(\d+(?:\.\d+)?)(?:\b|[\s\])])""",
        RegexOption.IGNORE_CASE,
    )

    fun parseVolumeNumber(chapterName: String, recognizeSeasonAsVolume: Boolean = false): Double? {
        VOLUME_REGEX.find(chapterName)?.groupValues?.get(1)?.toDoubleOrNull()?.let { return it }
        CJK_VOLUME_REGEX.find(chapterName)?.let { match ->
            (
                match.groupValues.getOrNull(1).takeUnless { it.isNullOrEmpty() }
                    ?: match.groupValues.getOrNull(2)
                )
                ?.toDoubleOrNull()
                ?.let { return it }
        }
        if (recognizeSeasonAsVolume) {
            SEASON_REGEX.find(chapterName)?.groupValues?.get(1)?.toDoubleOrNull()?.let { return it }
        }
        return null
    }
}
