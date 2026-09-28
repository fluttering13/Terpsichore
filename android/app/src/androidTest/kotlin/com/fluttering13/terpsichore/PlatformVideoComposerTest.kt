package com.fluttering13.terpsichore

import android.graphics.Color
import android.media.MediaMetadataRetriever
import androidx.test.platform.app.InstrumentationRegistry
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.ReturnCode
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID

class PlatformVideoComposerTest {
    @Test fun combinesDifferentSizesAndSilentClipInOrder() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val folder = File(context.cacheDir, "composer-test-${UUID.randomUUID()}").apply { mkdirs() }
        try {
            val red = File(folder, "red.mp4")
            val blue = File(folder, "blue.mp4")
            fun generate(args: List<String>) {
                assertTrue(ReturnCode.isSuccess(FFmpegKit.executeWithArguments(args.toTypedArray()).returnCode))
            }
            generate(listOf("-y", "-f", "lavfi", "-i", "color=red:s=160x90:r=30:d=0.6",
                "-f", "lavfi", "-i", "sine=frequency=440:duration=0.6", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", red.absolutePath))
            generate(listOf("-y", "-f", "lavfi", "-i", "color=blue:s=90x160:r=24:d=0.5", "-c:v", "libx264", "-pix_fmt", "yuv420p", blue.absolutePath))
            val composer = PlatformVideoComposer({}, {})
            assertTrue(composer.hasAudio(composer.probe(red)))
            assertFalse(composer.hasAudio(composer.probe(blue)))
            val progress = mutableListOf<Int>()
            val output = composer.combine(listOf(red, blue), folder) { index, _ -> progress += index }
            assertEquals(listOf(0, 1), progress)
            assertTrue(composer.hasAudio(composer.probe(output)))
            val media = MediaMetadataRetriever()
            try {
                media.setDataSource(output.absolutePath)
                assertEquals("160", media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH))
                assertEquals("90", media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT))
                val duration = media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toInt()
                assertTrue("duration=$duration", duration in 1050..1250)
                val first = media.getFrameAtTime(100000, MediaMetadataRetriever.OPTION_CLOSEST)!!
                val last = media.getFrameAtTime(900000, MediaMetadataRetriever.OPTION_CLOSEST)!!
                assertTrue(Color.red(first.getPixel(80, 45)) > 180)
                assertTrue(Color.blue(last.getPixel(80, 45)) > 180)
                // Portrait clip is letterboxed, not stretched/cropped.
                assertTrue(Color.blue(last.getPixel(5, 45)) < 20)
                first.recycle(); last.recycle()
            } finally { media.release() }
        } finally { folder.deleteRecursively() }
    }
}
