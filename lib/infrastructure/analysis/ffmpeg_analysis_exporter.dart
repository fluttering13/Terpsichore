import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/ab_analysis/analysis_exporter.dart';
import '../../core/ab_analysis/analysis_project.dart';

final class FfmpegAnalysisExporter implements AnalysisExporter {
  const FfmpegAnalysisExporter();

  @override
  Future<AnalysisExportResult> export(AnalysisExportRequest request) async {
    final project = request.project;
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/exports',
    );
    await directory.create(recursive: true);
    final outputPath =
        '${directory.path}/terpsichore_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final arguments = project.output == AnalysisOutput.sideBySide
        ? _sideBySideArguments(project, outputPath)
        : _trackBArguments(project, outputPath);
    final session = await FFmpegKit.executeWithArguments(arguments);
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode) && await File(outputPath).exists()) {
      return AnalysisExported(outputPath);
    }

    await File(outputPath).delete().catchError((_) => File(outputPath));
    final output = await session.getOutput();
    final reason = output == null || output.trim().isEmpty
        ? '影片輸出失敗，FFmpeg 回傳代碼：$returnCode'
        : '影片輸出失敗：${_lastUsefulLine(output)}';
    return AnalysisExportFailed(reason);
  }

  List<String> _sideBySideArguments(
    AnalysisProject project,
    String outputPath,
  ) {
    final a = project.trackA;
    final b = project.trackB;
    final custom = project.audioSource == AnalysisAudioSource.custom
        ? project.customAudio
        : null;
    final hasAudio =
        project.audioSource != AnalysisAudioSource.muted &&
        (project.audioSource != AnalysisAudioSource.custom || custom != null);
    final audioTrack = project.audioSource == AnalysisAudioSource.trackA
        ? a
        : b;
    final audioInput = switch (project.audioSource) {
      AnalysisAudioSource.trackA => '0:a?',
      AnalysisAudioSource.trackB => '1:a?',
      AnalysisAudioSource.custom => '2:a?',
      AnalysisAudioSource.muted => '',
    };
    final audioFilter = custom == null
        ? _audioTempoFilter(audioTrack.rate.value)
        : 'adelay=${custom.timelineStart.inMilliseconds}:all=1';
    final filter = [
      '[0:v]setpts=${_inverse(a.rate.value)}*PTS,'
          'scale=640:720:force_original_aspect_ratio=decrease,'
          'pad=640:720:(ow-iw)/2:(oh-ih)/2:black,setsar=1[a]',
      '[1:v]setpts=${_inverse(b.rate.value)}*PTS,'
          'scale=640:720:force_original_aspect_ratio=decrease,'
          'pad=640:720:(ow-iw)/2:(oh-ih)/2:black,setsar=1[b]',
      '[a][b]hstack=inputs=2[v]',
    ].join(';');
    return [
      '-y',
      '-ss',
      _seconds(a.trim.start),
      '-t',
      _seconds(a.trim.duration),
      '-i',
      a.source.path,
      '-ss',
      _seconds(b.trim.start),
      '-t',
      _seconds(b.trim.duration),
      '-i',
      b.source.path,
      if (custom != null) ...[
        '-ss',
        _seconds(custom.trim.start),
        '-t',
        _seconds(custom.trim.duration),
        '-i',
        custom.path,
      ],
      '-filter_complex',
      filter,
      '-map',
      '[v]',
      if (hasAudio) ...['-map', audioInput, '-filter:a', audioFilter],
      '-t',
      _seconds(project.sharedTimelineDuration),
      if (!hasAudio) '-an',
      ..._encodingArguments,
      outputPath,
    ];
  }

  List<String> _trackBArguments(AnalysisProject project, String outputPath) {
    final a = project.trackA;
    final b = project.trackB;
    final custom = project.audioSource == AnalysisAudioSource.custom
        ? project.customAudio
        : null;
    final hasAudio =
        project.audioSource != AnalysisAudioSource.muted &&
        (project.audioSource != AnalysisAudioSource.custom || custom != null);
    final audioTrack = project.audioSource == AnalysisAudioSource.trackA
        ? a
        : b;
    final audioInput = switch (project.audioSource) {
      AnalysisAudioSource.trackA => '0:a?',
      AnalysisAudioSource.trackB => '1:a?',
      AnalysisAudioSource.custom => '2:a?',
      AnalysisAudioSource.muted => '',
    };
    final audioFilter = custom == null
        ? _audioTempoFilter(audioTrack.rate.value)
        : 'adelay=${custom.timelineStart.inMilliseconds}:all=1';
    return [
      '-y',
      '-ss',
      _seconds(a.trim.start),
      '-t',
      _seconds(a.trim.duration),
      '-i',
      a.source.path,
      '-ss',
      _seconds(b.trim.start),
      '-t',
      _seconds(b.trim.duration),
      '-i',
      b.source.path,
      if (custom != null) ...[
        '-ss',
        _seconds(custom.trim.start),
        '-t',
        _seconds(custom.trim.duration),
        '-i',
        custom.path,
      ],
      '-vf',
      'setpts=${_inverse(b.rate.value)}*PTS,setsar=1',
      '-map',
      '1:v:0',
      if (hasAudio) ...['-map', audioInput, '-filter:a', audioFilter],
      '-t',
      _seconds(b.effectiveDuration),
      if (!hasAudio) '-an',
      ..._encodingArguments,
      outputPath,
    ];
  }

  static const _encodingArguments = [
    '-c:v',
    'mpeg4',
    '-q:v',
    '4',
    '-pix_fmt',
    'yuv420p',
    '-r',
    '30',
    '-c:a',
    'aac',
    '-b:a',
    '128k',
    '-movflags',
    '+faststart',
  ];

  String _seconds(Duration value) =>
      (value.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(
        6,
      );

  String _inverse(double rate) => (1 / rate).toStringAsFixed(8);

  String _audioTempoFilter(double rate) {
    final filters = <String>[];
    var remaining = rate;
    while (remaining < 0.5) {
      filters.add('atempo=0.5');
      remaining /= 0.5;
    }
    filters.add('atempo=${remaining.toStringAsFixed(8)}');
    return filters.join(',');
  }

  String _lastUsefulLine(String output) {
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '未知錯誤';
    final line = lines.last;
    return line.length <= 180 ? line : line.substring(line.length - 180);
  }
}
