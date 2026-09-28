package com.fluttering13.terpsichore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PlatformDownloadPolicyTest {
    @Test fun validatesSupportedHostsWithoutAcceptingSpoofedDomains() {
        assertEquals("https://m.youtube.com/watch?v=abc", PlatformDownloadPolicy.validateUrl("https://m.youtube.com/watch?v=abc"))
        assertEquals("https://www.threads.net/@test/post/abc", PlatformDownloadPolicy.validateUrl("https://www.threads.net/@test/post/abc"))
        assertEquals("https://www.facebook.com/share/r/18Lvd3oRBQ/", PlatformDownloadPolicy.validateUrl("https://www.facebook.com/share/r/18Lvd3oRBQ/"))
        assertEquals("https://instagram.com/reel/abc/?x=a%26b", PlatformDownloadPolicy.validateUrl("https://instagram.com/reel/abc/?x=a%26b"))
        listOf("https://instagram.com/dancer/", "https://facebook.com/dancer/", "https://threads.com/@dancer").forEach {
            assertThrows(DownloadFailure::class.java) { PlatformDownloadPolicy.validateUrl(it) }
        }
        listOf("https://youtube.com.evil.test/watch?v=x", "https://evil.test/youtube.com", "file:///tmp/video", "https://u:p@youtube.com/watch?v=x", "https://youtube.com/playlist?list=x").forEach {
            assertThrows(DownloadFailure::class.java) { PlatformDownloadPolicy.validateUrl(it) }
        }
    }

    @Test fun mapsAccessFailuresSeparatelyFromNetworkAndStorage() {
        assertEquals("ACCESS_RESTRICTED", PlatformDownloadPolicy.errorCode("This video is private"))
        assertEquals("ACCESS_RESTRICTED", PlatformDownloadPolicy.errorCode("Sign in to confirm you're not a bot"))
        assertEquals("ACCESS_RESTRICTED", PlatformDownloadPolicy.errorCode("HTTP Error 403: Forbidden"))
        assertEquals("RATE_LIMITED", PlatformDownloadPolicy.errorCode("HTTP Error 429"))
        assertEquals("NETWORK", PlatformDownloadPolicy.errorCode("Connection timed out"))
        assertEquals("STORAGE_FULL", PlatformDownloadPolicy.errorCode("No space left on device"))
        assertEquals("PROTECTED", PlatformDownloadPolicy.errorCode("This video is DRM protected"))
        assertEquals("EXTRACTION_FAILED", PlatformDownloadPolicy.errorCode("Unexpected extraction error"))
    }
}
