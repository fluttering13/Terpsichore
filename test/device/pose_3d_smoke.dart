// Foreground Android smoke test. Restore the normal lib/main.dart APK afterwards.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terpsichore/core/ab_analysis/analysis_project.dart';
import 'package:terpsichore/core/ab_analysis/pose_3d.dart';
import 'package:terpsichore/core/shared_video_playback/playback_rate.dart';
import 'package:terpsichore/core/shared_video_playback/time_range.dart';
import 'package:terpsichore/core/shared_video_playback/video_source.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/pose_3d_view.dart';
import 'package:terpsichore/infrastructure/analysis/pose_3d_analyzer.dart';
import 'package:terpsichore/infrastructure/analysis/pose_3d_exporter.dart';
import 'package:video_player/video_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('3D smoke test');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder(
            valueListenable: status,
            builder: (_, value, _) => Text(value),
          ),
        ),
      ),
    ),
  );
  final dir = await getApplicationSupportDirectory();
  final report = <String, Object?>{'status': 'running'};
  final resultFile = File('${dir.path}/pose3d-smoke.json');
  Future<void> save() =>
      resultFile.writeAsString(jsonEncode(report), flush: true);
  await save();
  try {
    AnalysisTrack track(String side, int start, int end, double rate) =>
        AnalysisTrack(
          source: VideoSource(
            id: side,
            path: '${dir.path}/thunder-airflare-${side.toLowerCase()}.mp4',
            label: side,
          ),
          mediaDuration: Duration(milliseconds: side == 'A' ? 1333 : 4245),
          trim: TimeRange(
            start: Duration(milliseconds: start),
            end: Duration(milliseconds: end),
          ),
          rate: PlaybackRate.ab(rate),
        );
    final project = AnalysisProject(
      trackA: track('A', 200, 800, .5),
      trackB: track('B', 400, 2000, 1.25),
      output: AnalysisOutput.sideBySide,
    );
    final analyzer = Pose3dAnalyzer();
    final timer = Stopwatch()..start();
    final data = await analyzer.analyze(
      project,
      const Pose3dSettings(fps: 3),
      (p, s) => status.value = 'NLF $s ${(p * 100).round()}%',
    );
    report['inferenceMs'] = timer.elapsedMilliseconds;
    report['performance'] = analyzer.performance;
    report['duration'] = data.seconds;
    report['aFrames'] = data.a.frames.length;
    report['bFrames'] = data.b.frames.length;
    report['aDetected'] = data.a.frames.where((f) => f.points != null).length;
    report['bDetected'] = data.b.frames.where((f) => f.points != null).length;
    if (report['aDetected'] == 0 || report['bDetected'] == 0) {
      throw StateError('No pose');
    }
    final file = await Pose3dExporter().export(
      data,
      Pose3dCamera(yaw: .65, pitch: .25, zoom: 1.1),
      (p) => status.value = 'Export ${(p * 100).round()}%',
    );
    final saved = await file.copy('${dir.path}/pose3d-smoke.mp4');
    await file.delete();
    final player = VideoPlayerController.file(saved);
    try {
      await player.initialize();
      report['exportBytes'] = await saved.length();
      report['exportWidth'] = player.value.size.width;
      report['exportHeight'] = player.value.size.height;
      report['exportDurationMs'] = player.value.duration.inMilliseconds;
      if (player.value.size != const Size(720, 720)) {
        throw StateError('Wrong export resolution');
      }
      if ((player.value.duration.inMilliseconds - 1200).abs() > 40) {
        throw StateError('Wrong export duration');
      }
    } finally {
      await player.dispose();
    }
    report['status'] = 'passed';
    status.value = '3D inference + rotated-camera MP4 passed';
  } catch (e, st) {
    report['status'] = 'failed';
    report['error'] = '$e';
    report['stack'] = '$st';
    status.value = 'Failed: $e';
  } finally {
    await save();
  }
}
