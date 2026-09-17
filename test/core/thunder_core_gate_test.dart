import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';
import 'package:terpsichore/core/ab_analysis/thunder_crop_tracking.dart';

PoseFrame frame(
  double t, {
  double dx = 0,
  bool hidden = false,
  bool inverted = false,
}) => PoseFrame(
  t,
  List.generate(
    17,
    (j) => PosePoint(
      .4 + dx + (j % 2) * .1,
      inverted ? 1 - (.2 + j * .025) : .2 + j * .025,
      hidden && j == 5 ? .1 : .9,
    ),
  ),
);

void main() {
  test('core grace needs three shared points and small displacement', () {
    expect(thunderCoreGrace(frame(.1, hidden: true), frame(0), 1), isTrue);
    expect(
      thunderCoreGrace(frame(.1, dx: .3, hidden: true), frame(0), 1),
      isFalse,
    );
    expect(thunderCoreGrace(frame(.3, hidden: true), frame(0), 1), isFalse);
  });
  test(
    'retry order is deterministic, excludes first direction, retains fallback',
    () {
      expect(thunderRetryOrder(2, [.4, .8, .9, .6]), [1, 3, 0]);
      expect(thunderRetryOrder(0, [0, 0, 0, 0]), [1, 2, 3]);
    },
  );
  test('early exit requires trusted core and adequate body confidence', () {
    expect(thunderCanStopRetry(frame(.1), frame(0), 1), isTrue);
    expect(thunderCanStopRetry(frame(.1), null, 1), isFalse);
    expect(thunderCanStopRetry(frame(.1, dx: .3), frame(0), 1), isFalse);
    expect(thunderCanStopRetry(frame(.1, hidden: true), frame(0), 1), isFalse);
  });
  test(
    'core accepts small motion, rejects jump, missing torso and stale anchor',
    () {
      final a = frame(0);
      expect(thunderCoreStable(frame(.1, dx: .01), a, 1), isTrue);
      expect(thunderCoreStable(frame(.1, dx: .2), a, 1), isFalse);
      expect(thunderCoreStable(frame(.1, hidden: true), a, 1), isFalse);
      expect(thunderCoreStable(frame(.5), a, 1), isFalse);
      expect(thunderCoreStable(a, null, 1), isFalse);
    },
  );
  test(
    'low confidence limbs and upside-down orientation do not trigger alone',
    () {
      final a = frame(0, inverted: true);
      final b = frame(.1, inverted: true);
      final p = List<PosePoint>.of(b.points);
      for (final j in [7, 8, 9, 10, 13, 14, 15, 16]) {
        p[j] = const PosePoint(0, 0, .1);
      }
      expect(thunderCoreStable(PoseFrame(.1, p), a, 1), isTrue);
    },
  );
}
