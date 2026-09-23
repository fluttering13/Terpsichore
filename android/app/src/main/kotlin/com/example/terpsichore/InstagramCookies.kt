package com.example.terpsichore

/** Accept only Instagram cookies; never retain unrelated browser sessions. */
internal object InstagramCookies {
    fun normalize(text: String, now: Long = System.currentTimeMillis() / 1000): String {
        if (text.length > 1024 * 1024) throw DownloadFailure("IG_INVALID_COOKIES")
        val rows = text.lineSequence().mapNotNull { raw ->
            val line = raw.trimEnd('\r').removePrefix("#HttpOnly_")
            if (line.isBlank() || line.startsWith('#')) return@mapNotNull null
            val fields = line.split('\t')
            if (fields.size != 7) throw DownloadFailure("IG_INVALID_COOKIES")
            val domain = fields[0].removePrefix(".").lowercase()
            if (domain != "instagram.com" && !domain.endsWith(".instagram.com")) return@mapNotNull null
            if (fields[1] !in listOf("TRUE", "FALSE") || fields[3] !in listOf("TRUE", "FALSE") ||
                !fields[2].startsWith('/') || !Regex("[A-Za-z0-9_-]+").matches(fields[5]) ||
                fields[6].any { it.isISOControl() }) throw DownloadFailure("IG_INVALID_COOKIES")
            val expiry = fields[4].toLongOrNull() ?: throw DownloadFailure("IG_INVALID_COOKIES")
            if (expiry != 0L && expiry <= now) return@mapNotNull null
            fields
        }.toList()
        if (rows.none { it[5] == "sessionid" && it[6].isNotBlank() &&
                it[0].removePrefix(".") in listOf("instagram.com", "www.instagram.com") && it[2] == "/" }) {
            throw DownloadFailure("IG_INVALID_COOKIES")
        }
        return "# Netscape HTTP Cookie File\n" + rows.joinToString("\n") { it.joinToString("\t") } + "\n"
    }

    fun fromWebView(header: String): String = normalize(
        "# Netscape HTTP Cookie File\n" + header.split(';').mapNotNull { cookie ->
            val pair = cookie.trim().split('=', limit = 2)
            if (pair.size != 2) null else ".instagram.com\tTRUE\t/\tTRUE\t0\t${pair[0]}\t${pair[1]}"
        }.joinToString("\n"),
    )
}
