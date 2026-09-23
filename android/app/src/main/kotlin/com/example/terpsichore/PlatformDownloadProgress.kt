package com.example.terpsichore

/** Tracks separate media streams without treating each stream as the whole job. */
internal class PlatformDownloadProgress(private val streamCount: Int) {
    private val streams = mutableMapOf<String, Double>()
    private var fraction = 0.0
    private var merging = false

    fun accept(line: String): Pair<String, Double>? {
        if (line.startsWith("[Merger]") || line.startsWith("[VideoRemuxer]") ||
            line.startsWith("[Fixup")) {
            merging = true
            fraction = maxOf(fraction, 0.9)
            return "merging" to fraction
        }
        if (merging || !line.startsWith("terpsichore-progress:")) return null
        val parts = line.trim().split(':')
        if (parts.size != 5 || parts[1].isBlank()) return null
        val previous = streams[parts[1]] ?: 0.0
        val downloaded = parts[3].toDoubleOrNull()
        val total = parts[4].toDoubleOrNull()
        val current = if (parts[2] == "finished") 1.0 else {
            if (downloaded == null || total == null || !downloaded.isFinite() ||
                !total.isFinite() || downloaded < 0 || total <= 0) return null
            (downloaded / total).coerceIn(0.0, 1.0)
        }
        streams[parts[1]] = maxOf(previous, current)
        fraction = maxOf(fraction, (streams.values.sum() / streamCount * 0.9).coerceAtMost(0.9))
        return (if (streamCount > 1 && streams.size > 1) "audio" else "downloading") to fraction
    }

    companion object {
        const val TEMPLATE = "download:terpsichore-progress:%(info.format_id)s:%(progress.status)s:%(progress.downloaded_bytes)s:%(progress.total_bytes,progress.total_bytes_estimate)s"

        fun inspectionPhase(line: String): String? = when {
            !line.startsWith("[") -> null
            line.contains("Downloading webpage", ignoreCase = true) -> "connecting"
            line.contains("Downloading", ignoreCase = true) -> "metadata"
            else -> null
        }
    }
}
