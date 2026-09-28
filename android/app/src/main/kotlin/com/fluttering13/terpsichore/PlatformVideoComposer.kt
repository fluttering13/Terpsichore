package com.fluttering13.terpsichore

import com.antonkarpenko.ffmpegkit.FFmpegKitConfig
import com.antonkarpenko.ffmpegkit.FFmpegSession
import com.antonkarpenko.ffmpegkit.FFprobeSession
import com.antonkarpenko.ffmpegkit.LogRedirectionStrategy
import com.antonkarpenko.ffmpegkit.ReturnCode
import org.json.JSONObject
import java.io.File
import kotlin.math.roundToInt

/** Local files only. Normalize clips individually to bound decoder/memory usage. */
internal class PlatformVideoComposer(
    private val checkCancelled: () -> Unit,
    private val sessionChanged: (Long?) -> Unit,
) {
    fun probe(file: File): JSONObject {
        checkCancelled()
        val session = FFprobeSession.create(arrayOf("-v", "error", "-show_streams", "-show_format", "-of", "json", file.absolutePath), null, null, LogRedirectionStrategy.NEVER_PRINT_LOGS)
        sessionChanged(session.sessionId)
        try {
            checkCancelled()
            FFmpegKitConfig.ffprobeExecute(session)
            checkCancelled()
            check(ReturnCode.isSuccess(session.returnCode)) { "MEDIA_PROBE_FAILED" }
            return JSONObject(session.output)
        } finally { sessionChanged(null) }
    }

    fun hasAudio(info: JSONObject): Boolean = streams(info).any { it.optString("codec_type") == "audio" }
    private fun streams(info: JSONObject): List<JSONObject> {
        val array = info.optJSONArray("streams") ?: return emptyList()
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
    }

    private fun run(args: List<String>) {
        checkCancelled()
        val session = FFmpegSession.create(args.toTypedArray(), null, null, null, LogRedirectionStrategy.NEVER_PRINT_LOGS)
        sessionChanged(session.sessionId)
        try {
            checkCancelled()
            FFmpegKitConfig.ffmpegExecute(session)
            checkCancelled()
            check(ReturnCode.isSuccess(session.returnCode)) { "COMBINE_FAILED" }
        } finally { sessionChanged(null) }
    }

    fun combine(files: List<File>, folder: File, progress: (Int, Int) -> Unit): File {
        val first = streams(probe(files.first())).first { it.optString("codec_type") == "video" }
        var sourceWidth = first.optInt("width", 720).coerceAtLeast(2)
        var sourceHeight = first.optInt("height", 1280).coerceAtLeast(2)
        val side = first.optJSONArray("side_data_list")
        val rotation = (0 until (side?.length() ?: 0)).mapNotNull { side?.optJSONObject(it) }
            .firstOrNull { it.has("rotation") }?.optInt("rotation") ?: first.optJSONObject("tags")?.optInt("rotate", 0) ?: 0
        if (kotlin.math.abs(rotation) % 180 == 90) {
            val temp = sourceWidth; sourceWidth = sourceHeight; sourceHeight = temp
        }
        val scale = minOf(1.0, 1920.0 / maxOf(sourceWidth, sourceHeight), 1080.0 / minOf(sourceWidth, sourceHeight))
        val width = ((sourceWidth * scale / 2).roundToInt() * 2).coerceAtLeast(2)
        val height = ((sourceHeight * scale / 2).roundToInt() * 2).coerceAtLeast(2)
        val clips = files.mapIndexed { index, file ->
            progress(index, files.size)
            val audio = hasAudio(probe(file))
            val output = File(folder, "normalized-$index.mp4")
            val args = mutableListOf("-y", "-i", file.absolutePath)
            if (!audio) args += listOf("-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo")
            args += listOf("-map", "0:v:0", "-map", if (audio) "0:a:0" else "1:a:0",
                "-vf", "scale=$width:$height:force_original_aspect_ratio=decrease:force_divisible_by=2,pad=$width:$height:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,setpts=PTS-STARTPTS",
                "-af", "aresample=48000:async=1:first_pts=0,apad", "-shortest",
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "192k", "-map_metadata", "-1", output.absolutePath)
            run(args)
            output
        }
        val list = File(folder, "concat.txt")
        // Generated names only; never interpolate source titles or URLs.
        list.writeText(clips.joinToString("\n") { "file '${it.name}'" })
        val output = File(folder, "combined.mp4")
        run(listOf("-y", "-f", "concat", "-safe", "1", "-i", list.absolutePath, "-c", "copy", "-movflags", "+faststart", output.absolutePath))
        check(hasAudio(probe(output))) { "AUDIO_MISSING" }
        return output
    }
}
