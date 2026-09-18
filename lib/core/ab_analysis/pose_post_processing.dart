import 'dart:math' as math;
import 'pose_alignment.dart';

/// Centered coordinate median, without filling missing observations or crossing
/// a joint's missing-frame boundary (adjusted for explicit sampling FPS).
/// Raw input remains untouched.
PoseSequence medianPoseSequence(PoseSequence raw, double windowSeconds) {
  final window = windowSeconds.isFinite ? math.max(0.0, windowSeconds) : 0.0;
  final frames = raw.frames;
  bool valid(PosePoint p) => p.score >= .15 && p.x.isFinite && p.y.isFinite;
  double median(List<double> values) {
    values.sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }

  return PoseSequence(
    List.generate(frames.length, (i) {
      return PoseFrame(
        frames[i].seconds,
        List.generate(17, (joint) {
          final original = frames[i].points[joint];
          if (!valid(original)) return const PosePoint(0, 0, 0);
          var left = i, right = i;
          while (left > 0 &&
              valid(frames[left - 1].points[joint]) &&
              frames[left].seconds - frames[left - 1].seconds <=
                  raw.gapLimit(.2) + 1e-8 &&
              frames[i].seconds - frames[left - 1].seconds <=
                  window / 2 + 1e-8) {
            left--;
          }
          while (right + 1 < frames.length &&
              valid(frames[right + 1].points[joint]) &&
              frames[right + 1].seconds - frames[right].seconds <=
                  raw.gapLimit(.2) + 1e-8 &&
              frames[right + 1].seconds - frames[i].seconds <=
                  window / 2 + 1e-8) {
            right++;
          }
          if (right - left < 2) return original;
          final points = frames
              .sublist(left, right + 1)
              .map((f) => f.points[joint]);
          return PosePoint(
            median(points.map((p) => p.x).toList()),
            median(points.map((p) => p.y).toList()),
            original.score,
          );
        }),
      );
    }),
    raw.aspectRatio,
    samplingFps: raw.samplingFps,
  );
}

/// Source-time, display-only processing. Never feeds invented evidence to alignment.
PoseSequence smoothPoseSequence(PoseSequence raw, double windowSeconds) {
  if (!windowSeconds.isFinite || windowSeconds <= 0 || raw.frames.isEmpty) {
    return raw;
  }
  final window = windowSeconds.clamp(0.0, 1.0);
  final frames = raw.frames;
  final segment = List.filled(frames.length, 0);
  bool valid(PosePoint p) => p.score >= .3 && p.x.isFinite && p.y.isFinite;
  double distance(PosePoint a, PosePoint b) => math.sqrt(
    math.pow((a.x - b.x) * raw.aspectRatio, 2) + math.pow(a.y - b.y, 2),
  );
  for (var i = 1; i < frames.length; i++) {
    final a = frames[i - 1];
    final b = frames[i];
    final rootJump =
        [5, 6, 11, 12]
            .where(
              (j) =>
                  valid(a.points[j]) &&
                  valid(b.points[j]) &&
                  distance(a.points[j], b.points[j]) > .35,
            )
            .length >=
        3;
    segment[i] =
        segment[i - 1] +
        ((b.seconds - a.seconds > .3 || b.seconds <= a.seconds || rootJump)
            ? 1
            : 0);
  }
  final filled = frames.map((f) => List<PosePoint>.of(f.points)).toList();
  for (var joint = 0; joint < 17; joint++) {
    var left = -1;
    for (var right = 0; right < frames.length; right++) {
      if (!valid(frames[right].points[joint])) continue;
      if (left >= 0 && right > left + 1 && segment[left] == segment[right]) {
        final dt = frames[right].seconds - frames[left].seconds;
        final a = frames[left].points[joint];
        final b = frames[right].points[joint];
        if (dt <= math.min(window, .25) + 1e-8 && distance(a, b) <= .35) {
          for (var k = left + 1; k < right; k++) {
            final t = (frames[k].seconds - frames[left].seconds) / dt;
            filled[k][joint] = PosePoint(
              a.x + (b.x - a.x) * t,
              a.y + (b.y - a.y) * t,
              math.min(a.score, b.score) * .5,
              inferred: true,
            );
          }
        }
      }
      left = right;
    }
  }
  final output = <PoseFrame>[];
  for (var i = 0; i < frames.length; i++) {
    final points = <PosePoint>[];
    for (var joint = 0; joint < 17; joint++) {
      final original = filled[i][joint];
      if (!valid(original) && !original.inferred) {
        points.add(original);
        continue;
      }
      final indices = <int>[];
      for (var k = 0; k < frames.length; k++) {
        if (segment[k] != segment[i] ||
            (frames[k].seconds - frames[i].seconds).abs() > window / 2) {
          continue;
        }
        // A long unfilled joint gap is a boundary even if the torso remains visible.
        final low = math.min(i, k);
        final high = math.max(i, k);
        if (List.generate(
          high - low + 1,
          (n) => low + n,
        ).any((n) => !valid(filled[n][joint]) && !filled[n][joint].inferred)) {
          continue;
        }
        indices.add(k);
      }
      if (indices.length < 3) {
        points.add(original);
        continue;
      }
      final weights = indices.map((k) {
        final dt = (frames[k].seconds - frames[i].seconds) / (window / 2);
        return math.exp(-2 * dt * dt) * math.pow(filled[k][joint].score, 2);
      }).toList();
      // Local linear fit at t=0. Unlike a trailing average, it preserves constant velocity.
      (double, double, double, double) fit() {
        double s = 0, st = 0, stt = 0, sx = 0, sy = 0, stx = 0, sty = 0;
        for (var n = 0; n < indices.length; n++) {
          final k = indices[n];
          final t = frames[k].seconds - frames[i].seconds;
          final p = filled[k][joint];
          final w = weights[n];
          s += w;
          st += w * t;
          stt += w * t * t;
          sx += w * p.x;
          sy += w * p.y;
          stx += w * t * p.x;
          sty += w * t * p.y;
        }
        final determinant = s * stt - st * st;
        if (determinant.abs() < 1e-12) return (original.x, original.y, 0, 0);
        return (
          (sx * stt - stx * st) / determinant,
          (sy * stt - sty * st) / determinant,
          (s * stx - st * sx) / determinant,
          (s * sty - st * sy) / determinant,
        );
      }

      var model = fit();
      final residuals = indices.map((k) {
        final dt = frames[k].seconds - frames[i].seconds;
        return distance(
          filled[k][joint],
          PosePoint(model.$1 + model.$3 * dt, model.$2 + model.$4 * dt, 1),
        );
      }).toList();
      final sorted = List<double>.of(residuals)..sort();
      final scale = math.max(.005, sorted[sorted.length ~/ 2] * 1.5);
      for (var n = 0; n < weights.length; n++) {
        if (residuals[n] > scale) weights[n] *= scale / residuals[n];
      }
      model = fit();
      points.add(
        PosePoint(
          model.$1.clamp(0, 1),
          model.$2.clamp(0, 1),
          original.score,
          inferred: original.inferred,
        ),
      );
    }
    output.add(PoseFrame(frames[i].seconds, points));
  }
  return PoseSequence(output, raw.aspectRatio);
}
