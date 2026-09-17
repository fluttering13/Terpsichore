import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';
import 'package:terpsichore/core/ab_analysis/pose_continuity.dart';

PoseFrame pose(double t, double dx) => PoseFrame(
  t,
  List.generate(
    17,
    (j) => PosePoint(.4 + dx + (j % 2) * .1, .2 + j * .025, .9),
  ),
);

void main() {
  test('accept motion, reject majority joint jump, reject missing', () {
    final a = pose(0, 0);
    expect(continuityCost(a, pose(.1, .02), 1), lessThan(1));
    expect(continuityCost(a, pose(.1, .4), 1), greaterThan(1));
    expect(continuityCost(a, missingPose(.1), 1), double.infinity);
  });
  test('one moving joint does not trigger and gap tolerance is capped', () {
    final a = pose(0, 0);
    final b = pose(.1, 0);
    final points = List<PosePoint>.of(b.points);
    points[9] = const PosePoint(1, 1, .9);
    expect(continuityCost(a, PoseFrame(.1, points), 1), lessThan(1));
    expect(continuityCost(a, pose(10, .4), 1), greaterThan(1));
  });
}
