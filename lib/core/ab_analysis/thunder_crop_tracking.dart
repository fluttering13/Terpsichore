import 'dart:math' as math;
import 'pose_alignment.dart';
import 'rtmpose_processing.dart';

// Crop helpers add 1.25 padding, so this represents the full 640-square image.
const thunderFullFrame = PersonBox(64, 64, 576, 576, 1);

/// Short confidence-drop grace; caller limits consecutive use to two samples.
bool thunderCoreGrace(PoseFrame current, PoseFrame? previous, double aspect) {
  if (previous == null) return false;
  final dt = current.seconds - previous.seconds;
  if (dt <= 0 || dt > .2) return false;
  final shared = [5, 6, 11, 12].where((j) {
    final a = current.points[j], b = previous.points[j];
    return a.score >= .2 &&
        b.score >= .2 &&
        [a.x, a.y, b.x, b.y].every((v) => v.isFinite);
  }).toList();
  if (shared.length < 3) return false;
  final distances = shared.map((j) {
    final a = current.points[j], b = previous.points[j];
    return math.sqrt(
      math.pow((a.x - b.x) * aspect, 2) + math.pow(a.y - b.y, 2),
    );
  }).toList()..sort();
  double extent = 0;
  for (final a in shared) {
    for (final b in shared) {
      final p = previous.points[a], q = previous.points[b];
      extent = math.max(
        extent,
        math.sqrt(math.pow((p.x - q.x) * aspect, 2) + math.pow(p.y - q.y, 2)),
      );
    }
  }
  return distances.last <= math.max(.08, extent) * (.25 + 1.5 * dt);
}

/// Rank untried directions by recent measured confidence, retaining all fallbacks.
List<int> thunderRetryOrder(int first, List<double> quality) =>
    ([0, 1, 2, 3]..remove(first))..sort((a, b) {
      final order = quality[b].compareTo(quality[a]);
      return order == 0 ? a.compareTo(b) : order;
    });

bool thunderCanStopRetry(PoseFrame frame, PoseFrame? previous, double aspect) =>
    thunderCoreStable(frame, previous, aspect) &&
    frame.points.skip(5).where((p) => p.score >= .3).length >= 8 &&
    frame.points.skip(5).fold(0.0, (s, p) => s + p.score) / 12 >= .45;

/// Fast-path gate only, not a reason to discard a pose. Compare the same four
/// torso joints so changing visibility cannot move the apparent center.
bool thunderCoreStable(PoseFrame current, PoseFrame? previous, double aspect) {
  if (previous == null) return false;
  const torso = [5, 6, 11, 12];
  bool visible(PoseFrame f) => torso.every((j) {
    final p = f.points[j];
    return p.score >= .3 && p.x.isFinite && p.y.isFinite;
  });
  if (!visible(current) || !visible(previous)) return false;
  (double, double) center(PoseFrame f) => (
    torso.fold(0.0, (s, j) => s + f.points[j].x) * aspect / 4,
    torso.fold(0.0, (s, j) => s + f.points[j].y) / 4,
  );
  double length(PoseFrame f) {
    final sx = (f.points[5].x + f.points[6].x) / 2;
    final sy = (f.points[5].y + f.points[6].y) / 2;
    final hx = (f.points[11].x + f.points[12].x) / 2;
    final hy = (f.points[11].y + f.points[12].y) / 2;
    return math.sqrt(math.pow((sx - hx) * aspect, 2) + math.pow(sy - hy, 2));
  }

  final dt = current.seconds - previous.seconds;
  if (dt <= 0 || dt > .3) return false;
  final scale = math.max(.08, length(previous));
  final ratio = math.max(.08, length(current)) / scale;
  if (ratio < .65 || ratio > 1.55) return false;
  final a = center(current), b = center(previous);
  final displacement = math.sqrt(
    math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2),
  );
  return displacement <= scale * (.25 + 1.5 * dt);
}

/// Original letterbox coordinates, using torso/body expansion around the hips.
PersonBox thunderNextCrop(PoseFrame frame, double aspect) {
  final p = frame.points;
  bool visible(int j) => p[j].score >= .2 && p[j].x.isFinite && p[j].y.isFinite;
  final hips = [11, 12].where(visible).toList();
  if (hips.isEmpty || ![5, 6].any(visible)) return thunderFullFrame;
  final cw = aspect >= 1 ? 640.0 : (640 * aspect).floorToDouble();
  final ch = aspect >= 1 ? (640 / aspect).floorToDouble() : 640.0;
  final px = ((640 - cw) / 2).floorToDouble(),
      py = ((640 - ch) / 2).floorToDouble();
  final cx = hips.fold(0.0, (s, j) => s + p[j].x * cw + px) / hips.length;
  final cy = hips.fold(0.0, (s, j) => s + p[j].y * ch + py) / hips.length;
  double torso = 0, body = 0;
  for (var j = 0; j < 17; j++) {
    if (!visible(j)) continue;
    final extent = math.max(
      (p[j].x * cw + px - cx).abs(),
      (p[j].y * ch + py - cy).abs(),
    );
    body = math.max(body, extent);
    if ([5, 6, 11, 12].contains(j)) torso = math.max(torso, extent);
  }
  final half = math.max(64.0, math.max(torso * 1.9, body * 1.2));
  if (half >= 320 || !half.isFinite) return thunderFullFrame;
  final inner = half / 1.25;
  return PersonBox(cx - inner, cy - inner, cx + inner, cy + inner, 1);
}

/// Continuity guard, not person identification.
bool thunderSameSubject(PoseFrame current, PoseFrame? previous, double aspect) {
  if (previous == null) return true;
  final distances = <double>[];
  for (final j in [5, 6, 11, 12]) {
    final a = current.points[j], b = previous.points[j];
    if (a.score >= .2 && b.score >= .2) {
      distances.add(
        math.sqrt(math.pow((a.x - b.x) * aspect, 2) + math.pow(a.y - b.y, 2)),
      );
    }
  }
  if (distances.length < 2) return true;
  distances.sort();
  return distances[distances.length ~/ 2] <= .3;
}
