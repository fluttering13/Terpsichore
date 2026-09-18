import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';
import 'package:terpsichore/core/ab_analysis/pose_post_processing.dart';

PoseFrame frame(double time, double x) => PoseFrame(
  time,
  List.generate(17, (i) => PosePoint(x + (i % 2) * .1, i < 11 ? .2 : .7, .9)),
);

void main() {
  test('a known frame after a missing interval remains available', () {
    final last = frame(2, .4);
    for (final fps in [null, 1, 5, 30]) {
      final sequence = PoseSequence([frame(0, .2), last], 1, samplingFps: fps);
      expect(sequence.at(1), isNull);
      expect(sequence.at(2), same(last));
    }
  });

  test(
    'invalid sampling metadata cannot interpolate through missing seconds',
    () {
      for (final fps in [0, -1]) {
        final sequence = PoseSequence(
          [frame(0, .2), frame(2, .4)],
          1,
          samplingFps: fps,
        );
        expect(sequence.gapLimit(.3), .3);
        expect(sequence.at(1), isNull);
      }
    },
  );

  test('low FPS smoothing crosses regular cadence but not dropped frames', () {
    final sequence = PoseSequence(
      [frame(0, .1), frame(1, .9), frame(2, .2), frame(4, .8)],
      1,
      samplingFps: 1,
    );
    final filtered = medianPoseSequence(sequence, 10);
    expect(filtered.frames[1].points[0].x, .2);
    expect(filtered.frames.last.points[0].x, .8);
    expect(sequence.frames[1].points[0].x, .9);
    expect(filtered.samplingFps, 1);
  });

  test('all locked parameters are validated before either search pass', () {
    final sequence = PoseSequence([frame(0, .1), frame(1, .2)], 1);
    for (final start in [double.nan, double.infinity, -.1, 1.0]) {
      expect(
        solveThunderAlignment(
          PoseAlignmentRequest(
            a: sequence,
            b: sequence,
            aStart: 0,
            aEnd: 1,
            aRate: 1,
            bStart: 0,
            bEnd: 1,
            fixedBStart: start,
            searchFullRange: true,
          ),
        ),
        isNull,
      );
    }
    for (final rate in [double.nan, double.infinity, 0, .09, 4.01]) {
      expect(
        solveThunderAlignment(
          PoseAlignmentRequest(
            a: sequence,
            b: sequence,
            aStart: 0,
            aEnd: 1,
            aRate: 1,
            bStart: 0,
            bEnd: 1,
            fixedBRate: rate.toDouble(),
            searchFullRange: true,
          ),
        ),
        isNull,
      );
    }
  });

  test('invalid B bounds cannot hide behind valid legacy anchors', () {
    final sequence = PoseSequence([frame(0, .1), frame(1, .2)], 1);
    for (final bounds in [
      (double.nan, 1.0),
      (0.0, double.infinity),
      (2.0, 1.0),
    ]) {
      expect(
        solveThunderAlignment(
          PoseAlignmentRequest(
            a: sequence,
            b: sequence,
            aStart: 0,
            aEnd: 1,
            aRate: 1,
            bStart: bounds.$1,
            bEnd: bounds.$2,
            bAnchorStart: 0,
            bAnchorEnd: 1,
          ),
        ),
        isNull,
      );
    }
  });

  test('exact observed samples align even when adjacent frames are missing', () {
    // The solver samples at the centers of sixty bins. Only three bins have
    // observations; those observations must still support a best-effort match.
    final sequence = PoseSequence([
      frame(.05, .1),
      frame(2.05, .2),
      frame(4.05, .3),
    ], 1);
    final result = solveThunderAlignment(
      PoseAlignmentRequest(
        a: sequence,
        b: sequence,
        aStart: 0,
        aEnd: 6,
        aRate: 1,
        bStart: 0,
        bEnd: 6,
        fixedBStart: 0,
        fixedBRate: 1,
        searchFullRange: true,
      ),
    );
    expect(result, isNotNull);
    expect(result!.coverage, closeTo(3 / 60, 1e-8));
    expect(result.bestEffort, isTrue);
    expect(result.bStart, 0);
    expect(result.bRate, 1);
  });
}
