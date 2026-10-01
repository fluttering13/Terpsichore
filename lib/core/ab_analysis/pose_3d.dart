import 'dart:math' as math;
import 'analysis_project.dart';

/// Uses aggregate wall-time throughput, including concurrent A/B samples.
Duration? estimatePose3dRemaining(double progress, Duration elapsed) {
  if (!progress.isFinite || progress <= 0 || elapsed <= Duration.zero) {
    return null;
  }
  if (progress >= 1) return Duration.zero;
  return Duration(
    microseconds: (elapsed.inMicroseconds * (1 - progress) / progress).ceil(),
  );
}

enum Pose3dModel {
  nlfInt8('NLF-L INT8', 'nlf-int8');

  const Pose3dModel(this.label, this.backend);
  final String label;
  final String backend;
}

final class Pose3dSettings {
  const Pose3dSettings({
    this.model = Pose3dModel.nlfInt8,
    this.fps = 10,
    this.interpolate = true,
  });
  static const fpsOptions = [1, 2, 3, 5, 6, 8, 10, 12, 15, 24, 30];
  final Pose3dModel model;
  final int fps;
  final bool interpolate;
  Map<String, Object> toJson() => {
    'model': model.name,
    'fps': fps,
    'interpolate': interpolate,
  };
  factory Pose3dSettings.fromJson(Object? value) {
    final data = value is Map ? value : const {};
    return Pose3dSettings(
      model: Pose3dModel.values.firstWhere(
        (v) => v.name == data['model'],
        orElse: () => Pose3dModel.nlfInt8,
      ),
      fps: data['model'] != 'mediaPipeHeavy' && fpsOptions.contains(data['fps'])
          ? data['fps'] as int
          : 10,
      interpolate: data['interpolate'] is bool
          ? data['interpolate'] as bool
          : true,
    );
  }
}

final class Pose3dPoint {
  const Pose3dPoint(this.x, this.y, this.z, [this.confidence = 1]);
  final double x, y, z, confidence;
  bool get valid =>
      [x, y, z, confidence].every((n) => n.isFinite) && confidence >= .2;
  Pose3dPoint lerp(Pose3dPoint b, double t) => Pose3dPoint(
    x + (b.x - x) * t,
    y + (b.y - y) * t,
    z + (b.z - z) * t,
    math.min(confidence, b.confidence),
  );
}

final class Pose3dFrame {
  const Pose3dFrame(this.seconds, this.points, {this.interpolated = false});
  final double seconds;
  // Preserve raw failures; bounded gap repair is applied only during interpolation.
  final List<Pose3dPoint>? points;
  final bool interpolated;
}

const pose3dBones = [
  (0, 1),
  (1, 2),
  (2, 3),
  (0, 4),
  (4, 5),
  (5, 6),
  (0, 7),
  (7, 8),
  (8, 9),
  (9, 10),
  (8, 11),
  (11, 12),
  (12, 13),
  (8, 14),
  (14, 15),
  (15, 16),
];

/// Times are in the adjusted, shared playback timeline, not source-video time.
List<double> pose3dSampleTimes(AnalysisProject project, int fps) {
  if (!Pose3dSettings.fpsOptions.contains(fps)) throw ArgumentError.value(fps);
  final duration = project.sharedTimelineDuration.inMicroseconds / 1e6;
  if (!duration.isFinite || duration <= 0) {
    throw ArgumentError('Empty timeline');
  }
  final count = (duration * fps).ceil();
  final result = List.generate(count, (i) => i / fps);
  // Cover the last output frame without reading past a source trim boundary.
  final last = math.max(0.0, duration - .001);
  if (last > result.last + .001) result.add(last);
  return result;
}

final class Pose3dSequence {
  Pose3dSequence(this.frames, this.samplingFps);
  final List<Pose3dFrame> frames;
  final int samplingFps;
  late final List<Pose3dFrame> _repaired = _repairShortGaps();

  List<Pose3dFrame> _repairShortGaps() {
    final result = List<Pose3dFrame>.of(frames);
    var i = 0;
    while (i < frames.length) {
      if (frames[i].points != null) {
        i++;
        continue;
      }
      final start = i;
      while (i < frames.length && frames[i].points == null) {
        i++;
      }
      // Never extrapolate at the edges or bridge long tracking losses.
      if (start == 0 || i == frames.length || i - start > 2) continue;
      final a = frames[start - 1], b = frames[i];
      final span = b.seconds - a.seconds;
      // Two missing samples at 5 FPS have valid endpoints 0.6 seconds apart.
      if (span <= 0 ||
          span > .6 + 1e-7 ||
          a.points!.length != b.points!.length) {
        continue;
      }
      for (var j = start; j < i; j++) {
        final t = (frames[j].seconds - a.seconds) / span;
        result[j] = Pose3dFrame(
          frames[j].seconds,
          List.generate(
            a.points!.length,
            (k) => a.points![k].lerp(b.points![k], t),
          ),
          interpolated: true,
        );
      }
    }
    return result;
  }

  Pose3dFrame at(double seconds, {required bool interpolate}) {
    final samples = interpolate ? _repaired : frames;
    if (samples.isEmpty) return Pose3dFrame(seconds, null);
    var lo = 0, hi = samples.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (samples[mid].seconds <= seconds) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final a = samples[lo];
    if (!interpolate ||
        lo == samples.length - 1 ||
        seconds <= a.seconds + 1e-7) {
      return a;
    }
    final b = samples[lo + 1];
    if (a.points == null ||
        b.points == null ||
        b.seconds - a.seconds > 1.6 / samplingFps) {
      return Pose3dFrame(seconds, null);
    }
    final t = ((seconds - a.seconds) / (b.seconds - a.seconds)).clamp(0.0, 1.0);
    return Pose3dFrame(
      seconds,
      List.generate(
        a.points!.length,
        (i) => a.points![i].lerp(b.points![i], t),
      ),
      interpolated: true,
    );
  }
}

final class Pose3dComparison {
  const Pose3dComparison(this.project, this.settings, this.a, this.b);
  final AnalysisProject project;
  final Pose3dSettings settings;
  final Pose3dSequence a, b;
  double get seconds => project.sharedTimelineDuration.inMicroseconds / 1e6;
}
