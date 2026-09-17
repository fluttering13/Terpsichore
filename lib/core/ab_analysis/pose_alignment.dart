import 'dart:math' as math;

import '../shared_video_playback/playback_rate.dart';

/// COCO-17 coordinates in the displayed, unmirrored video (0..1).
final class PosePoint {
  const PosePoint(this.x, this.y, this.score, {this.inferred = false});
  final double x;
  final double y;
  final double score;
  final bool inferred;
}

final class PoseFrame {
  const PoseFrame(this.seconds, this.points);
  final double seconds;
  final List<PosePoint> points;
}

final class PoseSequence {
  const PoseSequence(this.frames, this.aspectRatio);
  final List<PoseFrame> frames;
  final double aspectRatio;

  PoseFrame? at(double seconds) {
    if (frames.isEmpty ||
        seconds < frames.first.seconds - 0.09 ||
        seconds > frames.last.seconds + 0.18) {
      return null;
    }
    var lo = 0;
    var hi = frames.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (frames[mid].seconds < seconds) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == 0) return frames.first;
    final left = frames[lo - 1];
    final right = frames[lo];
    if (right.seconds - left.seconds > 0.3) return null;
    final t = ((seconds - left.seconds) / (right.seconds - left.seconds)).clamp(
      0.0,
      1.0,
    );
    return PoseFrame(
      seconds,
      List.generate(
        17,
        (i) => PosePoint(
          left.points[i].x * (1 - t) + right.points[i].x * t,
          left.points[i].y * (1 - t) + right.points[i].y * t,
          math.min(left.points[i].score, right.points[i].score),
          inferred: left.points[i].inferred || right.points[i].inferred,
        ),
      ),
    );
  }
}

final class PoseAlignmentRequest {
  const PoseAlignmentRequest({
    required this.a,
    required this.b,
    required this.aStart,
    required this.aEnd,
    required this.aRate,
    required this.bStart,
    required this.bEnd,
    this.mirrorA = false,
    this.mirrorB = false,
    this.bAnchorStart,
    this.bAnchorEnd,
    this.searchFraction = .1,
  });
  final PoseSequence a;
  final PoseSequence b;
  final double aStart, aEnd, aRate, bStart, bEnd;
  final bool mirrorA, mirrorB;
  final double? bAnchorStart, bAnchorEnd;
  final double searchFraction;
}

final class PoseAlignmentResult {
  const PoseAlignmentResult(
    this.bStart,
    this.bRate,
    this.error,
    this.coverage,
    this.ambiguous,
  );
  final double bStart, bRate, error, coverage;
  final bool ambiguous;
}

List<PosePoint>? _features(PoseFrame? frame, double aspect, bool mirrored) {
  if (frame == null) return null;
  final p = frame.points;
  if ([5, 6, 11, 12].any((i) => p[i].score < 0.15)) return null;
  final cx = (p[11].x + p[12].x) / 2;
  final cy = (p[11].y + p[12].y) / 2;
  final sx = (p[5].x + p[6].x) / 2;
  final sy = (p[5].y + p[6].y) / 2;
  final scale = math.sqrt(
    math.pow((cx - sx) * aspect, 2) + math.pow(cy - sy, 2),
  );
  if (scale < 0.025) return null;
  // Mirroring the display must also swap anatomical left/right labels.
  const flip = [0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15];
  return List.generate(12, (k) {
    final q = p[mirrored ? flip[k + 5] : k + 5];
    return PosePoint(
      (q.x - cx) * aspect / scale * (mirrored ? -1 : 1),
      (q.y - cy) / scale,
      q.score,
    );
  });
}

/// Thunder experiment objective: independent B offset/rate with unmatched tails.
/// Normalize BEFORE interpolation, matching the offline evaluation.
PoseAlignmentResult? solveThunderAlignment(PoseAlignmentRequest request) {
  final startAnchor = request.bAnchorStart ?? request.bStart;
  final endAnchor = request.bAnchorEnd ?? request.bEnd;
  final duration = (request.aEnd - request.aStart) / request.aRate;
  if (![
        startAnchor,
        endAnchor,
        duration,
        request.searchFraction,
      ].every((v) => v.isFinite) ||
      duration <= 0 ||
      endAnchor <= startAnchor ||
      request.aRate <= 0) {
    return null;
  }
  List<PosePoint>? sample(
    PoseSequence sequence,
    List<List<PosePoint>?> rows,
    double t,
  ) {
    final frames = sequence.frames;
    if (frames.isEmpty || t < frames.first.seconds || t > frames.last.seconds) {
      return null;
    }
    var lo = 0, hi = frames.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (frames[mid].seconds < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final left = math.max(0, lo - 1);
    final a = rows[left], b = rows[lo];
    final dt = frames[lo].seconds - frames[left].seconds;
    if (a == null || b == null || dt > .25) return null;
    final alpha = dt == 0 ? 0.0 : (t - frames[left].seconds) / dt;
    return List.generate(
      12,
      (j) => PosePoint(
        a[j].x * (1 - alpha) + b[j].x * alpha,
        a[j].y * (1 - alpha) + b[j].y * alpha,
        math.min(a[j].score, b[j].score),
      ),
    );
  }

  List<List<PosePoint>?> describe(PoseSequence sequence, bool mirror) =>
      sequence.frames.map((f) {
        final features = _features(f, sequence.aspectRatio, mirror);
        return features
            ?.map(
              (p) => PosePoint(
                p.x,
                p.y,
                p.score >= .15 ? math.max(.3, p.score) : 0,
              ),
            )
            .toList();
      }).toList();
  final ar = describe(request.a, request.mirrorA),
      br = describe(request.b, request.mirrorB);
  const count = 60;
  final times = List.generate(count, (i) => duration * (i + .5) / count);
  final af = times
      .map((t) => sample(request.a, ar, request.aStart + t * request.aRate))
      .toList();
  final radius =
      (endAnchor - startAnchor) * request.searchFraction.clamp(0.0, .5);
  final low = math.max(request.bStart, startAnchor - radius);
  final high = math.min(endAnchor, startAnchor + radius);
  PoseAlignmentResult? evaluate(double start, double rate) {
    if (math.min(duration * rate, endAnchor - start) <
        .6 * (endAnchor - startAnchor)) {
      return null;
    }
    var inside = 0, valid = 0, directions = 0;
    double cost = 0, weight = 0, direction = 0;
    List<PosePoint>? prevA, prevB;
    for (var i = 0; i < count; i++) {
      final source = start + times[i] * rate;
      if (source < startAnchor || source > endAnchor) {
        prevA = null;
        prevB = null;
        continue;
      }
      inside++;
      final a = af[i], b = sample(request.b, br, source);
      if (a == null ||
          b == null ||
          List.generate(
                12,
                (j) => j,
              ).where((j) => a[j].score >= .3 && b[j].score >= .3).length <
              6) {
        prevA = null;
        prevB = null;
        continue;
      }
      valid++;
      for (var j = 0; j < 12; j++) {
        if (a[j].score < .3 || b[j].score < .3) continue;
        final w = math.min(a[j].score, b[j].score);
        cost +=
            w *
            math.min(
              2.0,
              math.sqrt(
                math.pow(a[j].x - b[j].x, 2) + math.pow(a[j].y - b[j].y, 2),
              ),
            );
        weight += w;
        if (prevA != null &&
            prevB != null &&
            prevA[j].score >= .3 &&
            prevB[j].score >= .3) {
          final ax = a[j].x - prevA[j].x, ay = a[j].y - prevA[j].y;
          final bx = b[j].x - prevB[j].x, by = b[j].y - prevB[j].y;
          final norm = math.sqrt((ax * ax + ay * ay) * (bx * bx + by * by));
          if (norm > 1e-4) {
            direction += 1 - ((ax * bx + ay * by) / norm).clamp(-1.0, 1.0);
            directions++;
          }
        }
      }
      prevA = a;
      prevB = b;
    }
    if (inside < count * .8 || valid < count * .5 || weight == 0) return null;
    final coverage = valid / count;
    return PoseAlignmentResult(
      start,
      rate,
      cost / weight +
          .2 * (directions == 0 ? 1 : direction / directions) +
          .5 * (1 - coverage),
      coverage,
      false,
    );
  }

  final candidates = <PoseAlignmentResult>[];
  for (var s = low; s <= high + 1e-8; s += .05) {
    for (var r = .1; r <= 4 + 1e-8; r += .05) {
      final result = evaluate(s, r);
      if (result != null) candidates.add(result);
    }
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => a.error.compareTo(b.error));
  final seeds = <PoseAlignmentResult>[];
  for (final c in candidates) {
    if (!seeds.any(
      (s) => (s.bRate - c.bRate).abs() < .1 && (s.bStart - c.bStart).abs() < .1,
    )) {
      seeds.add(c);
    }
    if (seeds.length == 5) break;
  }
  for (final seed in seeds) {
    for (
      var s = math.max(low, seed.bStart - .05);
      s <= math.min(high, seed.bStart + .05) + 1e-8;
      s += .01
    ) {
      for (
        var r = math.max(.1, seed.bRate - .05);
        r <= math.min(4.0, seed.bRate + .05) + 1e-8;
        r += .005
      ) {
        final result = evaluate(s, r);
        if (result != null) candidates.add(result);
      }
    }
  }
  candidates.sort((a, b) => a.error.compareTo(b.error));
  final best = candidates.first;
  return PoseAlignmentResult(
    best.bStart,
    best.bRate.clamp(.1, 4.0),
    best.error,
    best.coverage,
    candidates.any(
      (c) =>
          ((c.bStart - best.bStart).abs() > .15 ||
              (c.bRate - best.bRate).abs() > .1) &&
          c.error < best.error + .015,
    ),
  );
}

/// Fixed A, full-coverage affine alignment of B. Run in a worker isolate.
PoseAlignmentResult? solvePoseAlignment(PoseAlignmentRequest request) {
  final duration = (request.aEnd - request.aStart) / request.aRate;
  if (!duration.isFinite ||
      duration <= 0 ||
      request.aEnd - request.aStart < 1 ||
      request.bEnd <= request.bStart) {
    return null;
  }
  final count = math.min(90, math.max(6, (duration * 12).floor()));
  final anchorStart = request.bAnchorStart;
  final anchorEnd = request.bAnchorEnd;
  final radius = anchorStart != null && anchorEnd != null
      ? (anchorEnd - anchorStart) * request.searchFraction.clamp(0.0, .5)
      : 0.0;
  final startMin = anchorStart == null
      ? request.bStart
      : math.max(request.bStart, anchorStart - radius);
  final startMax = anchorStart == null
      ? request.bEnd
      : math.min(request.bEnd, anchorStart + radius);
  final endMin = anchorEnd == null
      ? request.bStart
      : math.max(request.bStart, anchorEnd - radius);
  final endMax = anchorEnd == null
      ? request.bEnd
      : math.min(request.bEnd, anchorEnd + radius);
  final times = List.generate(count, (i) => duration * (i + 0.5) / count);
  final af = times
      .map(
        (t) => _features(
          request.a.at(request.aStart + t * request.aRate),
          request.a.aspectRatio,
          request.mirrorA,
        ),
      )
      .toList();
  if (af.whereType<List<PosePoint>>().length < count * 0.7) return null;
  // No temporal evidence in a static pose: do not invent a speed/offset.
  var movement = 0.0;
  var movementCount = 0;
  for (var i = 1; i < count; i++) {
    final x = af[i - 1];
    final y = af[i];
    if (x == null || y == null) continue;
    for (var j = 0; j < 12; j++) {
      if (x[j].score < 0.15 || y[j].score < 0.15) continue;
      movement += math.pow(x[j].x - y[j].x, 2) + math.pow(x[j].y - y[j].y, 2);
      movementCount++;
    }
  }
  if (movementCount == 0 || movement / movementCount < 0.0005) return null;

  PoseAlignmentResult? evaluate(double start, double rate) {
    final end = start + duration * rate;
    if (start < startMin - 0.000001 ||
        start > startMax + 0.000001 ||
        end < endMin - 0.000001 ||
        end > endMax + 0.000001 ||
        rate < .1 ||
        rate > PlaybackRate.abMaximum + 0.000001) {
      return null;
    }
    var sum = 0.0;
    var valid = 0;
    List<PosePoint>? previousB;
    for (var i = 0; i < count; i++) {
      final a = af[i];
      final b = _features(
        request.b.at(start + times[i] * rate),
        request.b.aspectRatio,
        request.mirrorB,
      );
      if (a == null || b == null) {
        previousB = null;
        continue;
      }
      var cost = 0.0;
      var weight = 0.0;
      var joints = 0;
      for (var j = 0; j < 12; j++) {
        final w = math.min(a[j].score, b[j].score).clamp(0.0, 1.0);
        if (w < 0.15) continue;
        final distance = math.sqrt(
          math.pow(a[j].x - b[j].x, 2) + math.pow(a[j].y - b[j].y, 2),
        );
        // Huber-style positional cost: isolated wrong joints have bounded influence.
        cost += w * (distance <= 1 ? distance * distance : 2 * distance - 1);
        final pa = i > 0 ? af[i - 1] : null;
        if (pa != null &&
            previousB != null &&
            pa[j].score >= .15 &&
            previousB[j].score >= .15) {
          final ax = a[j].x - pa[j].x, ay = a[j].y - pa[j].y;
          final bx = b[j].x - previousB[j].x, by = b[j].y - previousB[j].y;
          final an = math.sqrt(ax * ax + ay * ay),
              bn = math.sqrt(bx * bx + by * by);
          if (an > .02 && bn > .02) {
            cost +=
                .2 *
                w *
                (1 - ((ax * bx + ay * by) / (an * bn)).clamp(-1.0, 1.0));
          }
        }
        weight += w;
        joints++;
      }
      previousB = b;
      if (joints < 8) continue;
      sum += cost / weight + .1 * (1 - joints / 12);
      valid++;
    }
    if (valid < count * 0.7) return null;
    final coverage = valid / count;
    return PoseAlignmentResult(
      start,
      rate,
      sum / valid + 0.1 * (1 - coverage),
      coverage,
      false,
    );
  }

  final candidates = <PoseAlignmentResult>[];
  if (anchorStart != null && anchorEnd != null) {
    final initial = evaluate(anchorStart, (anchorEnd - anchorStart) / duration);
    if (initial != null) candidates.add(initial);
  }
  final maxRate = math.min(
    PlaybackRate.abMaximum,
    (request.bEnd - request.bStart) / duration,
  );
  for (var r = 0.1; r <= maxRate + 0.00001; r += 0.05) {
    final last = math.min(startMax, endMax - duration * r);
    for (var s = startMin; s <= last + 0.00001; s += 1 / 6) {
      final result = evaluate(s, r);
      if (result != null) candidates.add(result);
    }
    final result = evaluate(last, r);
    if (result != null) candidates.add(result);
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => a.error.compareTo(b.error));
  var best = candidates.first;
  final seeds = <PoseAlignmentResult>[];
  for (final candidate in candidates) {
    if (seeds.every(
      (s) =>
          (s.bStart - candidate.bStart).abs() > .15 ||
          (s.bRate - candidate.bRate).abs() > .04,
    )) {
      seeds.add(candidate);
    }
    if (seeds.length == 5) break;
  }
  for (final seed in seeds) {
    for (
      var r = math.max(0.1, seed.bRate - 0.05);
      r <= math.min(maxRate, seed.bRate + 0.05) + 0.000001;
      r += 0.002
    ) {
      for (
        var s = math.max(startMin, seed.bStart - 1 / 6);
        s <= seed.bStart + 1 / 6;
        s += 0.01
      ) {
        final result = evaluate(s, r);
        if (result != null && result.error < best.error) best = result;
      }
    }
  }
  final ambiguous = candidates.any(
    (c) => (c.bStart - best.bStart).abs() > 0.5 && c.error < best.error + 0.015,
  );
  if (best.error > 0.6) return null;
  return PoseAlignmentResult(
    best.bStart,
    best.bRate,
    best.error,
    best.coverage,
    ambiguous,
  );
}

/// Group heatmap peaks by associative embedding before selecting a person.
/// Ambiguous multi-person frames are rejected instead of mixing body parts.
PoseFrame decodeLitePose(List<double> values, double seconds, double aspect) {
  final groups = <List<(int, PosePoint, double)>>[];
  for (final joint in [
    5,
    6,
    11,
    12,
    7,
    8,
    13,
    14,
    9,
    10,
    15,
    16,
    0,
    1,
    2,
    3,
    4,
  ]) {
    for (var k = 0; k < 5; k++) {
      final offset = (joint * 5 + k) * 4;
      final score = values[offset + 2];
      if (!score.isFinite || score < 0.15) continue;
      final tag = values[offset + 3];
      var x = values[offset];
      var y = values[offset + 1];
      if (aspect > 1) {
        y = (y - (1 - 1 / aspect) / 2) * aspect;
      } else {
        x = (x - (1 - aspect) / 2) / aspect;
      }
      if (x < 0 || x > 1 || y < 0 || y > 1) continue;
      List<(int, PosePoint, double)>? match;
      var distance = 1.0;
      for (final group in groups) {
        if (group.any((p) => p.$1 == joint)) continue;
        final mean = group.fold(0.0, (sum, p) => sum + p.$3) / group.length;
        final d = (mean - tag).abs();
        if (d < distance) {
          distance = d;
          match = group;
        }
      }
      final point = (joint, PosePoint(x, y, score.clamp(0.0, 1.0)), tag);
      if (match == null) {
        groups.add([point]);
      } else {
        match.add(point);
      }
    }
  }
  final people = groups
      .where((g) => g.where((p) => p.$1 >= 5).length >= 8)
      .toList();
  final points = List.filled(17, const PosePoint(0, 0, 0));
  if (people.length == 1) {
    for (final p in people.single) {
      points[p.$1] = p.$2;
    }
  }
  return PoseFrame(seconds, points);
}
