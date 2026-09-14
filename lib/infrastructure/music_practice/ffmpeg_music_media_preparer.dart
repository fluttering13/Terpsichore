import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/music_practice/music_practice_source.dart';
import '../../core/music_practice/stem_separation.dart';
import 'pcm_wav.dart';

final class FfmpegMusicMediaPreparer implements MusicMediaPreparer {
  const FfmpegMusicMediaPreparer();

  @override
  Future<PreparedMusic> prepare(
    MusicPracticeSource source, {
    required void Function(StemSeparationUpdate update) onProgress,
  }) async {
    onProgress(
      const StemSeparationUpdate(
        stage: StemSeparationStage.preparingAudio,
        progress: 0,
      ),
    );
    final documents = await getApplicationDocumentsDirectory();
    final workspace = Directory(
      '${documents.path}/music_practice/${DateTime.now().millisecondsSinceEpoch}',
    );
    await workspace.create(recursive: true);
    final output = '${workspace.path}/original.wav';
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      source.path,
      '-vn',
      '-ac',
      '2',
      '-ar',
      '44100',
      '-c:a',
      'pcm_s16le',
      output,
    ]);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode) || !await File(output).exists()) {
      final details = (await session.getOutput())?.trim();
      throw StateError(
        details == null || details.isEmpty
            ? '無法從所選檔案讀取音樂'
            : details.contains('Output file does not contain any stream')
            ? '這個檔案沒有可用的音軌，請改選含音樂或聲音的檔案'
            : '音樂轉換失敗：${_lastLine(details)}',
      );
    }

    final reader = await Pcm16StereoWavReader.open(output);
    final duration = Duration(
      microseconds:
          (reader.frameCount * Duration.microsecondsPerSecond) ~/
          reader.sampleRate,
    );
    await reader.close();
    onProgress(
      const StemSeparationUpdate(
        stage: StemSeparationStage.preparingAudio,
        progress: 1,
      ),
    );
    return PreparedMusic(
      source: source,
      originalWavPath: output,
      workspacePath: workspace.path,
      duration: duration,
    );
  }

  String _lastLine(String output) {
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '未知原因';
    final line = lines.last;
    return line.length <= 160 ? line : line.substring(line.length - 160);
  }
}
