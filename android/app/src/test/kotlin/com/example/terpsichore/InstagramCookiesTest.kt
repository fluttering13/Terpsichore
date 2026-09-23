package com.example.terpsichore

import org.junit.Assert.*
import org.junit.Test

class InstagramCookiesTest {
    @Test fun importKeepsOnlyInstagramAndRequiresALiveSession() {
        val jar = "# Netscape HTTP Cookie File\n" +
            "#HttpOnly_.instagram.com\tTRUE\t/\tTRUE\t2000\tsessionid\ttest-session\n" +
            ".example.com\tTRUE\t/\tTRUE\t0\tsessionid\tother-secret\n" +
            ".instagram.com\tTRUE\t/\tTRUE\t900\told\texpired\n"
        val normalized = InstagramCookies.normalize(jar, 1000)
        assertTrue(normalized.contains("test-session"))
        assertFalse(normalized.contains("other-secret"))
        assertFalse(normalized.contains("expired"))
        try { InstagramCookies.normalize(jar, 3000); fail("Expired session accepted") }
        catch (e: DownloadFailure) { assertEquals("IG_INVALID_COOKIES", e.code) }
    }

    @Test fun webViewSessionConvertsWithoutSplittingCookieValue() {
        val jar = InstagramCookies.fromWebView("csrftoken=token; sessionid=a=b%3Ac; ds_user_id=123")
        assertTrue(jar.contains("\tsessionid\ta=b%3Ac"))
        assertTrue(jar.startsWith("# Netscape HTTP Cookie File"))
    }

    @Test fun unrelatedAndMalformedSessionsAreRejected() {
        for (text in listOf("sessionid=secret", ".instagram.com.evil.com\tTRUE\t/\tTRUE\t0\tsessionid\tsecret",
            ".instagram.com\tTRUE\t/\tTRUE\t0\tcsrftoken\tonly-csrf")) {
            try { InstagramCookies.normalize(text); fail("Invalid import accepted") }
            catch (e: DownloadFailure) { assertEquals("IG_INVALID_COOKIES", e.code) }
        }
    }

    @Test fun storyLinksAndPermissionErrorsRemainDistinct() {
        val url = PlatformDownloadPolicy.validateUrl("https://www.instagram.com/stories/dancer/12345/?x=1")
        assertTrue(PlatformDownloadPolicy.isStory(url))
        assertEquals("IG_LOGIN_REQUIRED", PlatformDownloadPolicy.instagramError("login required", false, true))
        assertEquals("IG_ACCESS_DENIED", PlatformDownloadPolicy.instagramError("You need to log in to access this content", true, true))
        assertEquals("IG_LOGIN_EXPIRED", PlatformDownloadPolicy.instagramError("login_required", true, true))
        assertEquals("IG_CHALLENGE_REQUIRED", PlatformDownloadPolicy.instagramError("checkpoint_required", true, true))
        assertEquals("IG_STORY_UNAVAILABLE", PlatformDownloadPolicy.instagramError("HTTP 404 not found", true, true))
        assertEquals("RATE_LIMITED", PlatformDownloadPolicy.instagramError("HTTP 429", true, true))
        for (invalid in listOf("https://www.instagram.com/stories/dancer/", "https://www.instagram.com/stories/highlights/1234/")) {
            try { PlatformDownloadPolicy.validateUrl(invalid); fail("Collection accepted") }
            catch (e: DownloadFailure) { assertEquals("VIDEO_LINK_REQUIRED", e.code) }
        }
    }
}
