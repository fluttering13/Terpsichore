import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';
import 'package:terpsichore/core/ab_analysis/pose_post_processing.dart';
import 'package:terpsichore/core/ab_analysis/movenet_processing.dart';

PoseFrame frame(double t, double x, {double score = .9}) =>
    PoseFrame(t, List.filled(17, PosePoint(x, .5, score)));

void main() {
  test('median removes spikes, keeps confidence and does not mutate input', () {
    final raw = PoseSequence([frame(0, .1), frame(.1, .9), frame(.2, .2)], 1);
    final result = medianPoseSequence(raw, .5);
    expect(result.frames[1].points[0].x, .2);
    expect(raw.frames[1].points[0].x, .9);
    expect(result.frames[1].points[0].score, .9);
    expect(result.frames[1].points[0].inferred, false);
  });
  test('median never fills low confidence or crosses a missing/time gap', () {
    final raw = PoseSequence([
      frame(0, .1),
      frame(.1, .9, score: .14),
      frame(.2, .2),
      frame(.5, .8),
    ], 1);
    final result = medianPoseSequence(raw, 1);
    expect(result.frames[1].points[0].score, 0);
    expect(result.frames[2].points[0].x, .2);
    expect(result.frames[3].points[0].x, .8);
    expect(medianPoseSequence(raw, 0).frames[0].points[0].x, .1);
  });
  test(
    'all four rotations preserve pixels and restore portrait coordinates',
    () {
      final input = Uint8List(640 * 640 * 3);
      input[(200 * 640 + 250) * 3] = 123;
      for (var k = 0; k < 4; k++) {
        final (x, y) = restorePosePixel(250, 200, (4 - k) % 4);
        final rotated = rotatePoseImage((input, k));
        expect(rotated[(y.toInt() * 640 + x.toInt()) * 3], 123);
        final restored = restoreMoveNet(
          PoseFrame(0, List.filled(17, PosePoint(x / 640, y / 640, .9))),
          9 / 16,
          k,
        );
        expect(restored.points.first.x, closeTo((250 - 140) / 360, 1e-9));
        expect(restored.points.first.y, closeTo(200 / 640, 1e-9));
      }
    },
  );
  PoseSequence motion(double duration, double rate) => PoseSequence(
    List.generate((duration * 12).round() + 1, (i) {
      final t = i / 12;
      final phase = t / rate;
      final points = List.generate(
        17,
        (j) => PosePoint(
          .3 + (j % 2) * .2 + (j == 9 ? .12 * math.sin(phase * 4) : 0),
          j == 5 || j == 6
              ? .3
              : j == 11 || j == 12
              ? .55
              : .6 + .1 * math.sin(phase * (j + 1)),
          .9,
        ),
      );
      return PoseFrame(t, points);
    }),
    1,
  );
  test(
    'independent rate keeps unmatched tail instead of forcing equal ends',
    () {
      final result = solveThunderAlignment(
        PoseAlignmentRequest(
          a: motion(3, 1),
          b: motion(4, 1),
          aStart: 0,
          aEnd: 3,
          aRate: 1,
          bStart: 0,
          bEnd: 4,
          searchFraction: 0,
        ),
      );
      expect(result, isNotNull);
      expect(result!.bStart, 0);
      expect(result.bRate, closeTo(1, .02));
    },
  );
  test('missing evidence and invalid ranges yield no proposal', () {
    final empty = PoseSequence([frame(0, 0, score: 0)], 1);
    expect(
      solveThunderAlignment(
        PoseAlignmentRequest(
          a: empty,
          b: empty,
          aStart: 0,
          aEnd: 3,
          aRate: 1,
          bStart: 0,
          bEnd: 4,
        ),
      ),
      isNull,
    );
    expect(
      solveThunderAlignment(
        PoseAlignmentRequest(
          a: empty,
          b: empty,
          aStart: 0,
          aEnd: 3,
          aRate: 0,
          bStart: 0,
          bEnd: 4,
        ),
      ),
      isNull,
    );
  });
}
