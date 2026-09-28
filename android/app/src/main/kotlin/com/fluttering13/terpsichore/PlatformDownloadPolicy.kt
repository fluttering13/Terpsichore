package com.fluttering13.terpsichore

import java.net.URI

/** Individual video links; Instagram stories may use an explicitly supplied session. */
object PlatformDownloadPolicy {
    private val domains = listOf("youtube.com", "youtu.be", "instagram.com", "facebook.com", "fb.watch", "threads.net", "threads.com")

    fun validateUrl(value: String): String {
        val uri = try { URI(value.trim()) } catch (_: Exception) { throw DownloadFailure("INVALID_URL") }
        val host = uri.host?.lowercase() ?: throw DownloadFailure("INVALID_URL")
        if (uri.scheme?.lowercase() !in listOf("http", "https") || uri.rawUserInfo != null ||
            uri.port !in listOf(-1, 80, 443) || domains.none { host == it || host.endsWith(".$it") }) {
            throw DownloadFailure("INVALID_URL")
        }
        val path = uri.path.orEmpty()
        val videoLink = when {
            host == "youtu.be" -> Regex("/[^/]+").matches(path.trimEnd('/'))
            host == "youtube.com" || host.endsWith(".youtube.com") ->
                (path == "/watch" && Regex("(?:^|&)v=[^&]+").containsMatchIn(uri.rawQuery.orEmpty())) ||
                    Regex("/(?:shorts|live|embed|v)/[^/]+").matches(path.trimEnd('/'))
            host == "instagram.com" || host.endsWith(".instagram.com") ->
                Regex("/(?:[^/]+/)?(?:p|reel|reels|tv)/[^/]+").matches(path.trimEnd('/')) ||
                    Regex("/stories/(?!highlights/)[A-Za-z0-9_.]+/[0-9]+").matches(path.trimEnd('/')) ||
                    Regex("/share/[^/]+(?:/[^/]+)?").matches(path.trimEnd('/'))
            host == "fb.watch" -> Regex("/[^/]+").matches(path.trimEnd('/'))
            host == "facebook.com" || host.endsWith(".facebook.com") ->
                Regex("/(?:share/|reel/|.*(?:videos|posts|permalink)/).+").matches(path) ||
                    (path.trimEnd('/') in listOf("/watch", "/video.php", "/story.php") &&
                        Regex("(?:^|&)(?:v|story_fbid)=[^&]+").containsMatchIn(uri.rawQuery.orEmpty()))
            else -> Regex("/(?:@[^/]+/post|t|share)/[^/]+").matches(path.trimEnd('/'))
        }
        if (!videoLink) {
            throw DownloadFailure("VIDEO_LINK_REQUIRED")
        }
        // Preserve escaped query values such as Facebook share parameters.
        return "https://$host${uri.rawPath}" + (uri.rawQuery?.let { "?$it" } ?: "")
    }

    fun errorCode(message: String): String {
        val text = message.lowercase()
        return when {
            listOf("no space left", "enospc", "disk full").any(text::contains) -> "STORAGE_FULL"
            listOf("private", "login", "log in", "sign in", "sign-in", "cookies", "members-only", "age-restricted", "age restricted", "permission", "403", "401", "forbidden", "not a bot", "authentication").any(text::contains) -> "ACCESS_RESTRICTED"
            listOf("429", "too many requests", "rate limit").any(text::contains) -> "RATE_LIMITED"
            listOf("timed out", "timeout", "name resolution", "network is unreachable", "unable to download webpage", "connection").any(text::contains) -> "NETWORK"
            listOf("removed", "deleted", "not available", "unavailable", "404").any(text::contains) -> "UNAVAILABLE"
            listOf("drm", "protected").any(text::contains) -> "PROTECTED"
            listOf("no video", "no downloadable", "no video formats").any(text::contains) -> "NO_VIDEO"
            else -> "EXTRACTION_FAILED"
        }
    }

    fun isInstagram(url: String): Boolean {
        val host = URI(url).host.orEmpty().lowercase()
        return host == "instagram.com" || host.endsWith(".instagram.com")
    }

    fun isStory(url: String) = isInstagram(url) && URI(url).path.startsWith("/stories/")

    fun instagramError(message: String, authenticated: Boolean, story: Boolean): String {
        val text = message.lowercase()
        return when {
            listOf("challenge_required", "checkpoint_required", "two-factor", "confirm your identity").any(text::contains) -> "IG_CHALLENGE_REQUIRED"
            listOf("login_required", "session expired", "not logged in").any(text::contains) -> "IG_LOGIN_EXPIRED"
            story && listOf("story has expired", "story is unavailable", "404", "not found").any(text::contains) -> "IG_STORY_UNAVAILABLE"
            errorCode(message) == "ACCESS_RESTRICTED" -> if (authenticated) "IG_ACCESS_DENIED" else "IG_LOGIN_REQUIRED"
            else -> errorCode(message)
        }
    }
}

class DownloadFailure(val code: String) : Exception(code)
