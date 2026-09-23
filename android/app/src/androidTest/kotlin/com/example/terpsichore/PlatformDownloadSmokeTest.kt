package com.example.terpsichore

import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Opt-in network test. Saves a video through MediaStore, verifies it, then deletes it. */
class PlatformDownloadSmokeTest {
    @Test fun downloadsSelectedCarouselPagesAndCombines() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("carouselSmoke") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        lateinit var engine: FlutterEngine
        lateinit var plugin: PlatformVideoDownloadPlugin
        instrumentation.runOnMainSync {
            engine = FlutterEngine(context)
            plugin = PlatformVideoDownloadPlugin()
            engine.plugins.add(plugin)
        }
        fun invoke(method: String, arguments: Map<String, Any>): Map<*, *> {
            val done = CountDownLatch(1)
            var response: Any? = null
            var error: String? = null
            instrumentation.runOnMainSync {
                plugin.onMethodCall(MethodCall(method, arguments), object : MethodChannel.Result {
                    override fun success(result: Any?) { response = result; done.countDown() }
                    override fun error(code: String, message: String?, details: Any?) { error = code; done.countDown() }
                    override fun notImplemented() { error = "NOT_IMPLEMENTED"; done.countDown() }
                })
            }
            assertTrue(done.await(5, TimeUnit.MINUTES))
            assertEquals("Native error in $method", null, error)
            return response as Map<*, *>
        }
        val saved = mutableListOf<Uri>()
        try {
            val video = invoke("inspect", mapOf("url" to requireNotNull(args.getString("videoUrl")), "jobId" to UUID.randomUUID().toString()))
            val entries = (video["entries"] as List<*>).map { it as Map<*, *> }
            assertEquals(9, entries.size)
            val selection = listOf(entries[1], entries[6]).map { entry ->
                val formats = (entry["formats"] as List<*>).map { it as Map<*, *> }
                val format = formats.minBy { (it["height"] as Int).takeIf { value -> value > 0 } ?: Int.MAX_VALUE }
                mapOf("snapshotId" to entry["snapshotId"]!!, "formatId" to format["id"]!!)
            }
            for (combine in listOf(false, true)) {
                val result = invoke("downloadSelection", mapOf("items" to selection, "combine" to combine, "jobId" to UUID.randomUUID().toString()))
                val uris = (result["uri"] as String).split('\n').filter { it.isNotBlank() }.map(Uri::parse)
                saved += uris
                assertEquals(result.toString(), if (combine) 1 else 2, uris.size)
                val issues = result["issues"] as List<*>
                assertTrue(issues.all { it.toString().endsWith(":AUDIO_NOT_FOUND") })
                if (combine) {
                    context.contentResolver.openFileDescriptor(uris.single(), "r")!!.use { descriptor ->
                        val media = MediaMetadataRetriever()
                        try {
                            media.setDataSource(descriptor.fileDescriptor)
                            assertEquals("yes", media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO))
                        } finally { media.release() }
                    }
                }
            }
        } finally {
            saved.forEach { context.contentResolver.delete(it, null, null) }
            instrumentation.runOnMainSync { engine.destroy() }
        }
    }

    @Test fun downloadsPublicVideoWithAudioToMediaStore() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("platformDownloadSmoke") == "true")
        val url = requireNotNull(args.getString("videoUrl"))
        val maxHeight = args.getString("maxHeight")?.toInt() ?: 720
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        lateinit var engine: FlutterEngine
        lateinit var plugin: PlatformVideoDownloadPlugin
        instrumentation.runOnMainSync {
            engine = FlutterEngine(context)
            plugin = PlatformVideoDownloadPlugin()
            engine.plugins.add(plugin)
        }
        fun invoke(method: String, arguments: Map<String, Any>): Map<*, *> {
            val done = CountDownLatch(1)
            var response: Any? = null
            var error: String? = null
            instrumentation.runOnMainSync {
                plugin.onMethodCall(MethodCall(method, arguments), object : MethodChannel.Result {
                    override fun success(result: Any?) { response = result; done.countDown() }
                    override fun error(code: String, message: String?, details: Any?) { error = code; done.countDown() }
                    override fun notImplemented() { error = "NOT_IMPLEMENTED"; done.countDown() }
                })
            }
            assertTrue("Timed out: $method", done.await(5, TimeUnit.MINUTES))
            assertEquals("Native error during $method", null, error)
            return response as Map<*, *>
        }
        var saved: Uri? = null
        try {
            val video = invoke("inspect", mapOf("url" to url, "jobId" to UUID.randomUUID().toString()))
            val formats = (video["formats"] as List<*>).map { it as Map<*, *> }
            assertTrue(formats.isNotEmpty())
            val selected = formats.firstOrNull { (it["height"] as Int) in 1..maxHeight } ?: formats.first()
            val receipt = invoke("download", mapOf("snapshotId" to video["snapshotId"]!!,
                "formatId" to selected["id"]!!, "jobId" to UUID.randomUUID().toString()))
            saved = Uri.parse(receipt["uri"] as String)
            assertEquals("content", saved.scheme)
            context.contentResolver.openFileDescriptor(saved, "r")!!.use { descriptor ->
                assertTrue(descriptor.statSize > 0)
                val media = MediaMetadataRetriever()
                try {
                    media.setDataSource(descriptor.fileDescriptor)
                    assertNotNull(media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH))
                    assertEquals("yes", media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO))
                } finally { media.release() }
            }
        } finally {
            saved?.let { context.contentResolver.delete(it, null, null) }
            instrumentation.runOnMainSync { engine.destroy() }
        }
    }
}
