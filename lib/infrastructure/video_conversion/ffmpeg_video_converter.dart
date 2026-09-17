import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/video_conversion/video_conversion.dart';

final class FfmpegVideoConverter implements VideoConverter {
  const FfmpegVideoConverter();

  @override
  Future<VideoMediaInfo> inspect(String inputPath) async {
    final session = await FFprobeKit.getMediaInformation(inputPath);
    final information = session.getMediaInformation();
    if (information == null) {
      throw const FormatException('無法讀取這個檔案的影片資訊');
    }
    final streams = information.getStreams();
    final video = streams
        .where((stream) => stream.getType() == 'video')
        .firstOrNull;
    final audio = streams
        .where((stream) => stream.getType() == 'audio')
        .firstOrNull;
    if (video == null) throw const FormatException('選取的檔案沒有影片軌');

    final seconds = double.tryParse(information.getDuration() ?? '');
    final rawFormat = information.getFormat() ?? 'unknown';
    return VideoMediaInfo(
      container: _friendlyContainer(rawFormat),
      videoCodec: video.getCodec()?.toUpperCase(),
      audioCodec: audio?.getCodec()?.toUpperCase(),
      duration: seconds == null
          ? null
          : Duration(milliseconds: (seconds * 1000).round()),
      width: video.getWidth(),
      height: video.getHeight(),
    );
  }

  @override
  Future<VideoConversionResult> convert({
    required String inputPath,
    required VideoOutputFormat outputFormat,
    required VideoQuality quality,
    required VideoCodec codec,
    required VideoResolution resolution,
    required Duration? inputDuration,
    void Function(VideoConversionProgress progress)? onProgress,
  }) async {
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/converted_videos',
    );
    await directory.create(recursive: true);
    final outputPath =
        '${directory.path}/terpsichore_${DateTime.now().millisecondsSinceEpoch}.${outputFormat.extension}';
    final arguments = [
      '-y',
      '-i',
      inputPath,
      '-map',
      '0:v:0',
      '-map',
      '0:a?',
      ...outputFormat.encodingArguments(
        quality: quality,
        codec: codec,
        resolution: resolution,
      ),
      if (outputFormat == VideoOutputFormat.mp4 ||
          outputFormat == VideoOutputFormat.mov) ...[
        '-movflags',
        '+faststart',
      ],
      outputPath,
    ];
    final completion = Completer<FFmpegSession>();
    await FFmpegKit.executeWithArgumentsAsync(
      arguments,
      (session) => completion.complete(session),
      null,
      (statistics) {
        final total = inputDuration;
        if (total == null) return;
        final processed = Duration(milliseconds: statistics.getTime());
        onProgress?.call(
          VideoConversionProgress(
            fraction: videoConversionFraction(
              processed: processed,
              total: total,
            ),
            processed: processed,
          ),
        );
      },
    );
    final session = await completion.future;
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode) && await File(outputPath).exists()) {
      onProgress?.call(
        VideoConversionProgress(
          fraction: 1,
          processed: inputDuration ?? Duration.zero,
        ),
      );
      return VideoConversionSucceeded(outputPath);
    }

    final outputFile = File(outputPath);
    if (await outputFile.exists()) await outputFile.delete();
    final log = (await session.getOutput())?.trim();
    return VideoConversionFailed(
      log == null || log.isEmpty ? '影片轉檔失敗（代碼：$returnCode）' : _lastLine(log),
    );
  }

  String _friendlyContainer(String format) {
    final values = format.toLowerCase().split(',');
    if (values.any((value) => value == 'mov' || value == 'mp4')) {
      return values.contains('mp4') ? 'MP4 / MOV' : 'MOV';
    }
    if (values.contains('matroska')) return 'Matroska (MKV)';
    if (values.contains('webm')) return 'WebM';
    if (values.contains('avi')) return 'AVI';
    return format.toUpperCase();
  }

  String _lastLine(String output) {
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '影片轉檔失敗';
    final line = lines.last;
    return line.length <= 180 ? line : line.substring(line.length - 180);
  }
}
