package com.example.terpsichore

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.ffmpeg.FFmpeg
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Runs extraction and media transfer off the UI thread. One cancellable job at a time. */
class PlatformVideoDownloadPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private var sink: EventChannel.EventSink? = null
    @Volatile private var attached = false
    @Volatile private var active: Job? = null
    private val snapshots = mutableMapOf<String, Snapshot>()
    private var initialized = false

    private class Job(val id: String) {
        @Volatile var cancelled = false
        @Volatile var timedOut = false
        var instagram = false
        var story = false
        @Volatile var mediaSession: Long? = null
        var item = 0
        var total = 0
        var offset = 0.0
        var weight = 1.0
        var cookieFile: File? = null
    }
    private data class Snapshot(val id: String, val info: JSONObject, val choices: List<Map<String, Any?>>, val url: String, val page: Int)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        attached = true
        channel = MethodChannel(binding.binaryMessenger, "terpsichore/platform_download")
        events = EventChannel(binding.binaryMessenger, "terpsichore/platform_download/progress")
        channel.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = false
        active?.let { cancel(it) }
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
        worker.shutdown()
        timer.shutdown()
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
    override fun onCancel(arguments: Any?) { sink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancel") {
            active?.takeIf { it.id == call.argument<String>("jobId") }?.let { cancel(it) }
            result.success(null)
            return
        }
        if (call.method !in listOf("inspect", "download", "downloadSelection")) { result.notImplemented(); return }
        if (active != null) { result.error("BUSY", "BUSY", null); return }
        val id = call.argument<String>("jobId")
        if (id == null || !Regex("[a-zA-Z0-9-]{1,80}").matches(id)) {
            result.error("INVALID_REQUEST", "INVALID_REQUEST", null); return
        }
        val job = Job(id)
        active = job
        val timeout = timer.schedule({ job.timedOut = true; cancel(job) },
            if (call.method == "inspect") 120L else 1800L, TimeUnit.SECONDS)
        worker.execute {
            try {
                emit(job, "initializing", null)
                initialize()
                checkCancelled(job)
                val response = if (call.method == "inspect") {
                    inspect(call.argument<String>("url").orEmpty(), job)
                } else if (call.method == "downloadSelection") {
                    downloadSelection(call.argument<List<Map<String, String>>>("items").orEmpty(), call.argument<Boolean>("combine") == true, job)
                } else {
                    download(call.argument<String>("snapshotId").orEmpty(), call.argument<String>("formatId").orEmpty(), job)
                }
                main.post { if (attached) result.success(response) }
            } catch (error: Exception) {
                val code = when {
                    job.timedOut -> "TIMEOUT"
                    job.cancelled || error is YoutubeDL.CanceledException -> "CANCELLED"
                    error is DownloadFailure -> error.code
                    error is SecurityException -> "STORAGE_PERMISSION"
                    job.instagram -> PlatformDownloadPolicy.instagramError(error.message.orEmpty(), job.cookieFile != null, job.story)
                    else -> PlatformDownloadPolicy.errorCode(error.message.orEmpty())
                }
                // Raw extractor output may contain signed URLs. Never expose it to UI/logs.
                main.post { if (attached) result.error(code, code, null) }
            } finally {
                job.cookieFile?.delete()
                timeout.cancel(false)
                main.post { if (active === job) active = null }
            }
        }
    }

    private fun cancel(job: Job) {
        job.cancelled = true
        // Repeat briefly to catch cancellation just before the subprocess registers itself.
        Thread {
            repeat(20) {
                if (active !== job) return@Thread
                YoutubeDL.getInstance().destroyProcessById(job.id)
                job.mediaSession?.let { com.antonkarpenko.ffmpegkit.FFmpegKit.cancel(it) }
                Thread.sleep(100)
            }
        }.start()
    }

    private fun checkCancelled(job: Job) {
        if (job.cancelled) throw DownloadFailure(if (job.timedOut) "TIMEOUT" else "CANCELLED")
    }

    private fun initialize() {
        if (initialized) return
        YoutubeDL.getInstance().init(context)
        // The wrapper ships an older extractor. Use our checksummed, release-pinned
        // bundle so initialization does not need to fetch executable code at runtime.
        val extractor = File(context.noBackupFilesDir, "${YoutubeDL.baseName}/${YoutubeDL.ytdlpDirName}/${YoutubeDL.ytdlpBin}")
        val staged = File(extractor.parentFile, "yt-dlp.new")
        context.assets.open("platform_downloader/yt-dlp").use { input ->
            staged.outputStream().use { input.copyTo(it) }
        }
        if (!staged.renameTo(extractor)) throw DownloadFailure("ENGINE_UNAVAILABLE")
        FFmpeg.getInstance().init(context)
        copyAssets("platform_downloader/plugins", File(context.filesDir, "platform-downloader-plugins"))
        initialized = true
    }

    private fun copyAssets(asset: String, destination: File) {
        val children = context.assets.list(asset).orEmpty()
        if (children.isEmpty()) {
            destination.parentFile?.mkdirs()
            context.assets.open(asset).use { input -> destination.outputStream().use { input.copyTo(it) } }
        } else {
            destination.mkdirs()
            children.forEach { copyAssets("$asset/$it", File(destination, it)) }
        }
    }

    private fun prepareSession(url: String, job: Job) {
        job.instagram = PlatformDownloadPolicy.isInstagram(url)
        job.story = PlatformDownloadPolicy.isStory(url)
        if (!job.instagram) return
        val cookies = InstagramSessionStore(context).read()
        if (cookies == null) {
            if (job.story) throw DownloadFailure("IG_LOGIN_REQUIRED")
            return
        }
        val file = File.createTempFile("instagram-job-", ".txt", context.cacheDir)
        job.cookieFile = file
        file.writeText(cookies)
    }

    private fun request(urls: List<String>, job: Job): YoutubeDLRequest = YoutubeDLRequest(urls).apply {
        addOption("--ignore-config")
        addOption("--no-playlist")
        addOption("--socket-timeout", "20")
        addOption("--retries", "2")
        addOption("--fragment-retries", "2")
        addOption("--no-warnings")
        addOption("--plugin-dirs", File(context.filesDir, "platform-downloader-plugins").absolutePath)
        job.cookieFile?.let { addOption("--cookies", it.absolutePath) }
    }

    private fun inspect(value: String, job: Job): Map<String, Any?> {
        snapshots.clear()
        val url = PlatformDownloadPolicy.validateUrl(value)
        prepareSession(url, job)
        val request = request(listOf(url), job).apply {
            addOption("--dump-single-json")
            addOption("--skip-download")
            addOption("--no-quiet")
        }
        emit(job, "connecting", null)
        val response = YoutubeDL.getInstance().execute(request, job.id) { _, _, line ->
            PlatformDownloadProgress.inspectionPhase(line)?.let { emit(job, it, null) }
        }
        checkCancelled(job)
        emit(job, "formats", null)
        // --no-quiet provides stage events before the final single-line JSON.
        val json = response.out.lineSequence().lastOrNull { it.trimStart().startsWith("{") }
            ?: throw DownloadFailure(if (job.story) "IG_STORY_UNAVAILABLE" else "EXTRACTION_FAILED")
        val root = JSONObject(json)
        val entries = root.optJSONArray("entries")
        if (entries == null) return describe(root, url, job, 1)
        val videos = (0 until entries.length()).mapNotNull { index ->
            val entry = entries.optJSONObject(index) ?: return@mapNotNull null
            try { describe(entry, url, job, entry.optInt("playlist_index", index + 1)) }
            catch (error: DownloadFailure) { if (error.code == "NO_VIDEO") null else throw error }
        }
        if (videos.isEmpty()) throw DownloadFailure("NO_VIDEO")
        return videos.first() + mapOf("entries" to videos)
    }

    private fun describe(info: JSONObject, url: String, job: Job, page: Int): Map<String, Any?> {
        if (info.optBoolean("is_live") || info.optString("live_status") == "is_upcoming") throw DownloadFailure("LIVE_UNSUPPORTED")
        if (info.optString("availability") in listOf("private", "premium_only", "subscriber_only", "needs_auth")) {
            throw DownloadFailure(if (!job.instagram) "ACCESS_RESTRICTED"
                else if (job.cookieFile == null) "IG_LOGIN_REQUIRED" else "IG_ACCESS_DENIED")
        }
        if (info.optBoolean("has_drm")) throw DownloadFailure("PROTECTED")
        val formats = info.optJSONArray("formats") ?: JSONArray().put(info)
        val all = (0 until formats.length()).mapNotNull { formats.optJSONObject(it) }
        val hasAudio = all.any { it.optString("vcodec") == "none" && it.optString("acodec") != "none" && !it.optBoolean("has_drm") }
        val choices = all.filter {
            it.optString("vcodec") != "none" && it.optString("ext") in listOf("mp4", "webm", "mov", "mkv") &&
                it.optString("url").startsWith("https://") && !it.optBoolean("has_drm") &&
                Regex("[a-zA-Z0-9_.-]+").matches(it.optString("format_id"))
        }.map { format ->
            val videoOnly = format.optString("acodec") == "none"
            mapOf<String, Any?>(
                "id" to format.getString("format_id"),
                "width" to format.optInt("width", 0), "height" to format.optInt("height", 0),
                "fps" to format.optDouble("fps", 0.0).takeIf { it.isFinite() },
                "bitrate" to format.optDouble("tbr", 0.0).takeIf { it.isFinite() },
                "extension" to format.optString("ext"),
                "bytes" to format.optLong("filesize", format.optLong("filesize_approx", 0)),
                "mergeAudio" to (videoOnly && hasAudio), "silent" to (videoOnly && !hasAudio),
            )
        }.distinctBy { it["id"] }.sortedWith(compareByDescending<Map<String, Any?>> { it["height"] as Int }
            .thenByDescending { (it["bitrate"] as? Double) ?: 0.0 })
        if (choices.isEmpty()) throw DownloadFailure("NO_VIDEO")
        val id = UUID.randomUUID().toString()
        snapshots[id] = Snapshot(id, info, choices, url, page)
        val thumbnails = info.optJSONArray("thumbnails") ?: JSONArray()
        val thumbnail = info.optString("thumbnail").takeIf { it.startsWith("https://") }
            ?: (thumbnails.length() - 1 downTo 0).asSequence()
                .mapNotNull { thumbnails.optJSONObject(it)?.optString("url") }
                .firstOrNull { it.startsWith("https://") }
        return mapOf("snapshotId" to id, "title" to info.optString("title", "Video"), "url" to url,
            "thumbnailUrl" to thumbnail,
            "platform" to info.optString("extractor", ""), "page" to page, "formats" to choices)
    }

    private fun download(snapshotId: String, formatId: String, job: Job): Map<String, Any?> {
        val current = snapshots[snapshotId] ?: throw DownloadFailure("EXPIRED")
        val choice = current.choices.firstOrNull { it["id"] == formatId } ?: throw DownloadFailure("EXPIRED")
        prepareSession(current.url, job)
        val folder = File(context.cacheDir, "platform-download-${UUID.randomUUID()}").apply { mkdirs() }
        try {
            val file = transfer(current, choice, folder, job)
            emit(job, "saving", 0.95)
            return save(file, current.info.optString("title", "Video"), job)
        } finally {
            // This directory was created above with a random name under our own cache.
            folder.deleteRecursively()
        }
    }

    private fun transfer(current: Snapshot, choice: Map<String, Any?>, folder: File, job: Job): File {
        val formatId = choice["id"] as String
            val metadata = File(folder, "source.json").apply { writeText(current.info.toString()) }
            val request = request(emptyList(), job).apply {
                addOption("--load-info-json", metadata.absolutePath)
                addOption("--format", if (choice["mergeAudio"] == true) "$formatId+bestaudio" else formatId)
                addOption("--merge-output-format", "mp4/mkv")
                addOption("--no-simulate")
                addOption("--no-mtime")
                addOption("--newline")
                addOption("--progress-template", PlatformDownloadProgress.TEMPLATE)
                addOption("--output", File(folder, "video.%(ext)s").absolutePath)
            }
            checkCancelled(job)
            emit(job, "downloading", 0.0)
            val progress = PlatformDownloadProgress(if (choice["mergeAudio"] == true) 2 else 1)
            YoutubeDL.getInstance().execute(request, job.id) { _, _, line ->
                progress.accept(line)?.let { (phase, fraction) -> emit(job, phase, fraction) }
            }
            checkCancelled(job)
            val file = folder.listFiles()?.singleOrNull { it.name.startsWith("video.") && it.extension in listOf("mp4", "webm", "mkv", "mov") && it.length() > 0 }
                ?: throw DownloadFailure("DOWNLOAD_FAILED")
        return file
    }

    private fun downloadSelection(items: List<Map<String, String>>, combine: Boolean, job: Job): Map<String, Any?> {
        if (items.isEmpty() || items.map { it["snapshotId"] }.distinct().size != items.size) throw DownloadFailure("INVALID_REQUEST")
        val selected = items.map { item ->
            val snapshot = snapshots[item["snapshotId"]] ?: throw DownloadFailure("EXPIRED")
            val choice = snapshot.choices.firstOrNull { it["id"] == item["formatId"] } ?: throw DownloadFailure("EXPIRED")
            snapshot to choice
        }.sortedBy { it.first.page }
        if (selected.map { it.first.url }.distinct().size != 1) throw DownloadFailure("INVALID_REQUEST")
        prepareSession(selected.first().first.url, job)
        val folder = File(context.cacheDir, "platform-batch-${UUID.randomUUID()}").apply { mkdirs() }
        val receipts = mutableListOf<Map<String, Any?>>()
        val issues = mutableListOf<String>()
        val files = mutableListOf<File>()
        val composer = PlatformVideoComposer({ checkCancelled(job) }, { job.mediaSession = it })
        job.total = selected.size
        try {
            for ((index, selection) in selected.withIndex()) {
                val (current, choice) = selection
                job.item = index + 1
                job.offset = index.toDouble() / selected.size * if (combine) 0.7 else 1.0
                job.weight = (if (combine) 0.7 else 1.0) / selected.size
                val itemFolder = File(folder, "item-$index").apply { mkdirs() }
                try {
                    checkCancelled(job)
                    emit(job, "downloading", 0.0)
                    val file = transfer(current, choice, itemFolder, job)
                    emit(job, "verifying", 0.94)
                    if (!composer.hasAudio(composer.probe(file))) {
                        if (choice["mergeAudio"] == true) throw DownloadFailure("AUDIO_MISSING")
                        issues += "${current.page}:AUDIO_NOT_FOUND"
                    }
                    if (combine) files += file else {
                        receipts += save(file, current.info.optString("title", "Video") + "_" + current.page.toString().padStart(2, '0'), job)
                        itemFolder.deleteRecursively()
                    }
                } catch (error: Exception) {
                    val code = when {
                        job.timedOut -> "TIMEOUT"
                        job.cancelled -> "CANCELLED"
                        error is DownloadFailure -> error.code
                        job.instagram -> PlatformDownloadPolicy.instagramError(error.message.orEmpty(), job.cookieFile != null, job.story)
                        else -> PlatformDownloadPolicy.errorCode(error.message.orEmpty())
                    }
                    issues += "${current.page}:$code"
                    // Never produce a combined file with silently omitted pages.
                    if (combine || job.cancelled) break
                }
            }
            if (combine && files.size == selected.size && !job.cancelled) {
                job.offset = 0.7
                job.weight = 0.25
                try {
                    val output = composer.combine(files, folder) { index, count ->
                        job.item = index + 1
                        emit(job, "combining", index.toDouble() / count)
                    }
                    job.offset = 0.95; job.weight = 0.05
                    receipts += save(output, selected.first().first.info.optString("title", "Video") + "_combined", job)
                } catch (error: Exception) {
                    issues += "0:${if (job.cancelled) "CANCELLED" else "COMBINE_FAILED"}"
                }
            }
            return mapOf("uri" to receipts.joinToString("\n") { it["uri"].toString() },
                "location" to receipts.joinToString("\n") { it["location"].toString() }, "issues" to issues)
        } finally {
            folder.deleteRecursively()
        }
    }

    private fun save(file: File, title: String, job: Job): Map<String, Any?> {
        val safeTitle = title.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_").take(60).trim().trimEnd('.')
        val name = "${safeTitle.ifBlank { "Terpsichore" }}-${UUID.randomUUID().toString().take(8)}.${file.extension}"
        if (Build.VERSION.SDK_INT >= 29) {
            val resolver = context.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, when (file.extension) { "webm" -> "video/webm"; "mkv" -> "video/x-matroska"; "mov" -> "video/quicktime"; else -> "video/mp4" })
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/Terpsichore")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: throw DownloadFailure("STORAGE_PERMISSION")
            try {
                resolver.openOutputStream(uri)?.use { output ->
                    file.inputStream().use { input ->
                        val bytes = ByteArray(128 * 1024)
                        var copied = 0L
                        var lastPercent = 95
                        while (true) {
                            checkCancelled(job)
                            val count = input.read(bytes)
                            if (count < 0) break
                            output.write(bytes, 0, count)
                            copied += count
                            val percent = (95 + 4 * copied / file.length()).toInt()
                            if (percent > lastPercent) {
                                lastPercent = percent
                                emit(job, "saving", percent / 100.0)
                            }
                        }
                    }
                } ?: throw DownloadFailure("STORAGE_PERMISSION")
                checkCancelled(job)
                values.clear(); values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                if (resolver.update(uri, values, null, null) != 1) throw DownloadFailure("STORAGE_PERMISSION")
                return mapOf("uri" to uri.toString(), "location" to "Download/Terpsichore/$name")
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
        }
        val directory = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: throw DownloadFailure("STORAGE_PERMISSION")
        val target = File(directory, name)
        try {
            file.copyTo(target)
            checkCancelled(job)
            return mapOf("uri" to target.toURI().toString(), "location" to target.absolutePath)
        } catch (e: Exception) { target.delete(); throw e }
    }

    private fun emit(job: Job, phase: String, progress: Double?) {
        val event = mapOf("jobId" to job.id, "phase" to phase, "progress" to progress?.let { job.offset + job.weight * it }, "item" to job.item, "total" to job.total)
        main.post { if (attached && active === job) sink?.success(event) }
    }
}
