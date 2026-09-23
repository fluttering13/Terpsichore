package com.example.terpsichore

import org.junit.Assert.*
import org.junit.Test

class PlatformDownloadProgressTest {
    @Test fun separateStreamsRetriesAndMergeNeverRegress() {
        val progress = PlatformDownloadProgress(2)
        assertEquals(0.225, progress.accept("terpsichore-progress:137:downloading:50:100")!!.second, 0.001)
        assertEquals(0.225, progress.accept("terpsichore-progress:137:downloading:10:100")!!.second, 0.001)
        assertEquals(0.45, progress.accept("terpsichore-progress:137:finished:100:100")!!.second, 0.001)
        val audio = progress.accept("terpsichore-progress:140:downloading:10:100")!!
        assertEquals("audio", audio.first)
        assertEquals(0.495, audio.second, 0.001)
        assertEquals(0.9, progress.accept("terpsichore-progress:140:finished:100:100")!!.second, 0.001)
        assertEquals("merging", progress.accept("[Merger] Merging formats")!!.first)
        assertNull(progress.accept("terpsichore-progress:140:downloading:1:100"))
    }

    @Test fun missingAndInvalidTotalsDoNotResetProgress() {
        val progress = PlatformDownloadProgress(1)
        assertNull(progress.accept("terpsichore-progress:18:downloading:20:NA"))
        assertNull(progress.accept("terpsichore-progress:18:downloading:NaN:100"))
        assertNull(progress.accept("terpsichore-progress:18:downloading:20:Infinity"))
        assertNull(progress.accept("[download] arbitrary output"))
        assertEquals(0.9, progress.accept("terpsichore-progress:18:finished:20:NA")!!.second, 0.001)
    }

    @Test fun inspectionOnlyExposesKnownStages() {
        assertEquals("connecting", PlatformDownloadProgress.inspectionPhase("[youtube] id: Downloading webpage"))
        assertEquals("metadata", PlatformDownloadProgress.inspectionPhase("[youtube] id: Downloading player API JSON"))
        assertNull(PlatformDownloadProgress.inspectionPhase("{\"title\":\"Downloading webpage\"}"))
        assertNull(PlatformDownloadProgress.inspectionPhase("https://example.com/private?token=secret"))
    }
}
