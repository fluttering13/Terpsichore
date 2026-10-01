import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/ab_analysis/analysis_project.dart';
import '../../core/ab_analysis/pose_3d.dart';

final class Pose3dCancelled implements Exception {}

final class Pose3dAnalyzer {
  static const _channel = MethodChannel('terpsichore/pose3d');
  bool cancelled = false;
  Map<String, dynamic>? performance;
  void _check() {
    if (cancelled) throw Pose3dCancelled();
  }

  Future<Pose3dComparison> analyze(
    AnalysisProject project,
    Pose3dSettings settings,
    void Function(double, String) onProgress, {
    VoidCallback? onInferenceStarted,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('3D Pose 目前支援 Android');
    }
    final times = pose3dSampleTimes(project, settings.fps);
    performance = await _channel.invokeMapMethod<String, dynamic>('configure', {
      'model': settings.model.backend,
    });
    var parallel = performance?['workers'] == 2;
    final sequences = List<Pose3dSequence?>.filled(2, null);
    final opened = <String>{};
    final completed = [0, 0];
    var aborted = false;
    Future<String> create(int side) async {
      _check();
      final track = side == 0 ? project.trackA : project.trackB;
      final id = await _channel.invokeMethod<String>('create', {
        'path': track.source.path,
        'model': settings.model.backend,
      });
      if (id == null) throw StateError('無法建立 3D 模型');
      opened.add(id);
      return id;
    }

    Future<void> run(int side, String id) async {
      final track = side == 0 ? project.trackA : project.trackB;
      try {
        final frames = <Pose3dFrame>[];
        for (var i = 0; i < times.length; i++) {
          _check();
          if (aborted) return;
          final sourceUs = project
              .sourcePositionAt(
                track,
                times[i] /
                    (project.sharedTimelineDuration.inMicroseconds / 1e6),
              )
              .inMicroseconds;
          final result = await _channel.invokeListMethod<num>('frame', {
            'id': id,
            'timeUs': sourceUs,
          });
          _check();
          List<Pose3dPoint>? points;
          if (result != null && result.length == 68) {
            points = List.generate(
              17,
              (j) => Pose3dPoint(
                result[j * 4].toDouble(),
                result[j * 4 + 1].toDouble(),
                result[j * 4 + 2].toDouble(),
                result[j * 4 + 3].toDouble(),
              ),
            );
            if (points.any(
              (p) => ![p.x, p.y, p.z, p.confidence].every((n) => n.isFinite),
            )) {
              points = null;
            }
          }
          frames.add(Pose3dFrame(times[i], points));
          completed[side]++;
          onProgress(
            (completed[0] + completed[1]) / (2 * times.length),
            parallel
                ? 'A+B'
                : side == 0
                ? 'A'
                : 'B',
          );
        }
        sequences[side] = Pose3dSequence(frames, settings.fps);
      } catch (_) {
        aborted = true;
        rethrow;
      }
    }

    try {
      final a = await create(0);
      String? b;
      if (parallel) {
        try {
          b = await create(1);
        } on PlatformException catch (e) {
          if (e.code != 'POSE3D_CAPACITY') rethrow;
          parallel =
              false; // Memory/thermal pressure changed while the first model loaded.
        }
      }
      onInferenceStarted?.call();
      if (parallel) {
        // Wait for both jobs before disposing either native tracking session, even on error.
        await Future.wait([run(0, a), run(1, b!)]);
      } else {
        await run(0, a);
        await _channel.invokeMethod<void>('close', {'id': a});
        opened.remove(a);
        b = await create(1);
        await run(1, b);
      }
      _check();
      return Pose3dComparison(project, settings, sequences[0]!, sequences[1]!);
    } finally {
      await Future.wait(
        opened.map((id) => _channel.invokeMethod<void>('close', {'id': id})),
      );
    }
  }
}
