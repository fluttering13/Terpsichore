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
      expect(result.bestEffort, isFalse);
    },
  );
  test('sparse evidence still provides a best effort proposal', () {
    final full = motion(3, 1);
    final sparse = PoseSequence(
      full.frames.where((f) => f.seconds <= .5).toList(),
      1,
    );
    final result = solveThunderAlignment(
      PoseAlignmentRequest(
        a: sparse,
        b: full,
        aStart: 0,
        aEnd: 3,
        aRate: 1,
        bStart: 0,
        bEnd: 3,
        searchFraction: 0,
      ),
    );
    expect(result, isNotNull);
    expect(result!.bestEffort, isTrue);
    expect(result.coverage, inExclusiveRange(0, .5));
    expect(result.bRate, closeTo(1, .03));
    expect(result.error.isFinite, isTrue);
  });
  test('short overlap is estimated when no full overlap is possible', () {
    final result = solveThunderAlignment(
      PoseAlignmentRequest(
        a: motion(3, 1),
        b: motion(.15, 1),
        aStart: 0,
        aEnd: 3,
        aRate: 1,
        bStart: 0,
        bEnd: .15,
        searchFraction: 0,
      ),
    );
    expect(result, isNotNull);
    expect(result!.bestEffort, isTrue);
    expect(result.coverage, inExclusiveRange(0, .8));
    expect(result.bStart, 0);
    expect(result.bRate, inInclusiveRange(.1, 4));
  });
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

  test('full search finds motion beyond the old anchor range', () {
    final reference = motion(3, 1);
    final shifted = PoseSequence(
      reference.frames.map((f) => PoseFrame(f.seconds + 6, f.points)).toList(),
      1,
    );
    final result = solveThunderAlignment(
      PoseAlignmentRequest(
        a: reference,
        b: shifted,
        aStart: 0,
        aEnd: 3,
        aRate: 1,
        bStart: 0,
        bEnd: 12,
        bAnchorStart: 0,
        bAnchorEnd: 2,
        searchFullRange: true,
      ),
    );
    expect(result, isNotNull);
    expect(result!.bStart, closeTo(6, .05));
    expect(result.bRate, closeTo(1, .02));
    expect(result.bestEffort, isFalse);
  });

  test(
    '1 to 5 FPS can interpolate and align without treating cadence as gaps',
    () {
      for (final fps in [1, 2, 3, 4, 5]) {
        final source = motion(3, 1);
        final sequence = PoseSequence(
          List.generate(3 * fps + 1, (i) {
            final t = i / fps;
            return PoseFrame(t, source.at(t)!.points);
          }),
          1,
          samplingFps: fps,
        );
        expect(sequence.at(.5 / fps), isNotNull);
        final processed = medianPoseSequence(sequence, 0);
        expect(processed.samplingFps, fps);
        final result = solveThunderAlignment(
          PoseAlignmentRequest(
            a: processed,
            b: sequence,
            aStart: 0,
            aEnd: 3,
            aRate: 1,
            bStart: 0,
            bEnd: 3,
            searchFraction: 0,
          ),
        );
        expect(result, isNotNull);
        expect(result!.bestEffort, isFalse);
        expect(result.bRate, closeTo(1, .02));
      }
      final missing = PoseSequence(
        [frame(0, .1), frame(2, .2)],
        1,
        samplingFps: 1,
      );
      expect(missing.at(1), isNull);
    },
  );

  test('smoothing windows above one second are not clamped', () {
    final sequence = PoseSequence(
      List.generate(31, (i) => frame(i / 10, i >= 11 && i <= 19 ? .9 : .1)),
      1,
    );
    expect(medianPoseSequence(sequence, 1).frames[15].points[0].x, .9);
    expect(medianPoseSequence(sequence, 3).frames[15].points[0].x, .1);
    expect(medianPoseSequence(sequence, 0).frames[15].points[0].x, .9);
  });

  test('locked B timeline preserves an off-grid start while finding speed', () {
    const start = 2.137;
    final target = motion(4.5, 1.5);
    final result = solveThunderAlignment(
      PoseAlignmentRequest(
        a: motion(3, 1),
        b: PoseSequence(
          target.frames
              .map((f) => PoseFrame(f.seconds + start, f.points))
              .toList(),
          1,
        ),
        aStart: 0,
        aEnd: 3,
        aRate: 1,
        bStart: start,
        bEnd: start + 4.5,
        fixedBStart: start,
        searchFullRange: true,
      ),
    );
    expect(result, isNotNull);
    expect(result!.bStart, start);
    expect(result.bRate, closeTo(1.5, .03));
    expect(result.bestEffort, isFalse);
  });

  test('locked B speed preserves an off-grid rate while finding start', () {
    const rate = 1.237;
    final target = motion(4, rate);
    final result = solveThunderAlignment(
      PoseAlignmentRequest(
        a: motion(3, 1),
        b: PoseSequence(
          target.frames.map((f) => PoseFrame(f.seconds + 2, f.points)).toList(),
          1,
        ),
        aStart: 0,
        aEnd: 3,
        aRate: 1,
        bStart: 0,
        bEnd: 6,
        fixedBRate: rate,
        searchFullRange: true,
      ),
    );
    expect(result, isNotNull);
    expect(result!.bRate, rate);
    expect(result.bStart, closeTo(2, .03));
    expect(result.bestEffort, isFalse);
  });

  test('best effort search also respects each B lock', () {
    final full = motion(3, 1);
    final sparse = PoseSequence(
      full.frames.where((f) => f.seconds <= .5).toList(),
      1,
    );
    for (final lockStart in [true, false]) {
      final result = solveThunderAlignment(
        PoseAlignmentRequest(
          a: sparse,
          b: full,
          aStart: 0,
          aEnd: 3,
          aRate: 1,
          bStart: 0,
          bEnd: 3,
          fixedBStart: lockStart ? .137 : null,
          fixedBRate: lockStart ? null : 1.237,
          searchFullRange: true,
        ),
      );
      expect(result, isNotNull);
      expect(result!.bestEffort, isTrue);
      if (lockStart) {
        expect(result.bStart, .137);
      } else {
        expect(result.bRate, 1.237);
      }
    }
  });
}
