import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/analysis_project.dart';
import 'package:terpsichore/core/ab_analysis/pose_3d.dart';
import 'package:terpsichore/core/shared_video_playback/playback_rate.dart';
import 'package:terpsichore/core/shared_video_playback/time_range.dart';
import 'package:terpsichore/core/shared_video_playback/video_source.dart';
import 'package:terpsichore/infrastructure/analysis/pose_3d_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory dir;
  AnalysisTrack track(String path, {double rate = 1}) => AnalysisTrack(
    source: VideoSource(id: path, path: path, label: path),
    mediaDuration: const Duration(seconds: 2),
    trim: TimeRange(start: Duration.zero, end: const Duration(seconds: 1)),
    rate: PlaybackRate(rate),
  );
  AnalysisProject project({double rate = 1}) => AnalysisProject(
    trackA: track('/a.mp4', rate: rate),
    trackB: track('/b.mp4'),
    output: AnalysisOutput.sideBySide,
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pose3d-cache-test-');
    messenger.setMockMethodCallHandler(channel, (_) async => dir.path);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });
  Future<void> save() async {
    final seq = Pose3dSequence([
      Pose3dFrame(0, List.filled(17, const Pose3dPoint(0, 0, 1))),
      const Pose3dFrame(.2, null),
    ], 5);
    await Pose3dCache.save(
      Pose3dComparison(project(), const Pose3dSettings(fps: 5), seq, seq),
    );
  }

  test(
    'cache rejects changed timing and preserves raw missing samples',
    () async {
      await save();
      final restored = await Pose3dCache.load(project());
      expect(restored!.b.frames.last.points, isNull);
      expect(await Pose3dCache.load(project(rate: .5)), isNull);
    },
  );
  test(
    'corrupt caches and malformed frame arrays are treated as misses',
    () async {
      final file = File('${dir.path}/pose3d-last.json');
      await file.writeAsString('{broken');
      expect(await Pose3dCache.load(project()), isNull);
      for (final damage in <void Function(Map<String, dynamic>)>[
        (d) => d['version'] = 999,
        (d) => d['settings']['model'] = 'retired',
        (d) => d['a'] = [],
        (d) => d['a'][1][0] = 0,
        (d) => d['a'][0][0] = -1,
        (d) => d['a'][0][1] = [
          [0, 0, 0, 1],
        ],
        (d) => d['a'][0][1][0][0] = 'invalid',
      ]) {
        await save();
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        damage(data);
        await file.writeAsString(jsonEncode(data));
        expect(await Pose3dCache.load(project()), isNull);
      }
    },
  );
}
