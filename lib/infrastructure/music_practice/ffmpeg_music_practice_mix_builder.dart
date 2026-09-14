import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';

import '../../core/music_practice/stem_separation.dart';

final class FfmpegMusicPracticeMixBuilder implements MusicPracticeMixBuilder {
  const FfmpegMusicPracticeMixBuilder();

  @override
  Future<String> build({
    required SeparatedStems stems,
    required Set<MusicStem> selection,
  }) async {
    if (selection.isEmpty) throw ArgumentError('至少要選擇一個分軌');
    final ordered = MusicStem.values.where(selection.contains).toList();
    if (ordered.length == 1) return stems.paths[ordered.single]!;
    final key = ordered.map((stem) => stem.name).join('_');
    final output = '${stems.prepared.workspacePath}/practice_$key.wav';
    if (await File(output).exists()) return output;

    final arguments = <String>['-y'];
    for (final stem in ordered) {
      arguments.addAll(['-i', stems.paths[stem]!]);
    }
    final inputs = List.generate(
      ordered.length,
      (index) => '[$index:a]',
    ).join();
    arguments.addAll([
      '-filter_complex',
      '$inputs'
          'amix=inputs=${ordered.length}:duration=longest:'
          'dropout_transition=0:normalize=0,alimiter=limit=0.98[a]',
      '-map',
      '[a]',
      '-c:a',
      'pcm_s16le',
      output,
    ]);
    final session = await FFmpegKit.executeWithArguments(arguments);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code) || !await File(output).exists()) {
      throw StateError('無法建立所選樂器的練習混音');
    }
    return output;
  }
}
