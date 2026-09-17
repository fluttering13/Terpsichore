import 'dart:math' as math;
import 'pose_alignment.dart';

bool continuityVisible(PoseFrame f) =>
    f.points.skip(5).where((p) => p.score >= .2).length >= 6 &&
    [5, 6].any((j) => f.points[j].score >= .2) &&
    [11, 12].any((j) => f.points[j].score >= .2);

/// Body-normalized multi-joint displacement. This is not identity recognition.
double continuityCost(PoseFrame a, PoseFrame b, double aspect) {
  if (!continuityVisible(a) || !continuityVisible(b)) return double.infinity;
  double distance(PosePoint x, PosePoint y) =>
      math.sqrt(math.pow((x.x - y.x) * aspect, 2) + math.pow(x.y - y.y, 2));
  final scales = <double>[];
  for (final pair in [(5, 11), (6, 12)]) {
    if (a.points[pair.$1].score >= .2 && a.points[pair.$2].score >= .2) {
      scales.add(distance(a.points[pair.$1], a.points[pair.$2]));
    }
  }
  final scale = math.max(.08, scales.isEmpty ? .15 : scales.reduce(math.max));
  final distances = <double>[];
  for (var j = 5; j < 17; j++) {
    if (a.points[j].score >= .2 && b.points[j].score >= .2) {
      distances.add(distance(a.points[j], b.points[j]) / scale);
    }
  }
  if (distances.length < 6) return double.infinity;
  distances.sort();
  // A moving limb alone must not trigger repair. Cap time tolerance so a long
  // missing segment cannot silently authorize a different person.
  final tolerance = .35 + 2.5 * (b.seconds - a.seconds).abs().clamp(0.0, .25);
  return distances[distances.length ~/ 2] / tolerance;
}

PoseFrame missingPose(double seconds) =>
    PoseFrame(seconds, List.filled(17, const PosePoint(0, 0, 0)));
