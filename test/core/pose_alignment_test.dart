import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';

List<PosePoint> pose(double t) => List.generate(17, (i) {
  const xy = [
    (0.5, 0.1),
    (0.48, 0.09),
    (0.52, 0.09),
    (0.46, 0.1),
    (0.54, 0.1),
    (0.4, 0.3),
    (0.6, 0.3),
    (0.32, 0.45),
    (0.68, 0.45),
    (0.25, 0.6),
    (0.75, 0.6),
    (0.43, 0.55),
    (0.57, 0.55),
    (0.4, 0.73),
    (0.6, 0.73),
    (0.4, 0.9),
    (0.6, 0.9),
  ];
  final moving = [7, 8, 9, 10, 13, 14, 15, 16].contains(i);
  return PosePoint(
    xy[i].$1 + (moving ? 0.09 * math.sin(t * (1.1 + i * 0.07)) : 0),
    xy[i].$2 + (moving ? 0.09 * math.sin(t * (1.7 + i * 0.11)) : 0),
    0.95,
  );
});

PoseSequence sequence(
  double end,
  double Function(double) clock, {
  bool mirror = false,
  double scale = 1,
  double shift = 0,
}) {
  const flip = [0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15];
  return PoseSequence(
    List.generate((end * 6).ceil() + 1, (i) {
      final p = pose(clock(i / 6));
      return PoseFrame(
        i / 6,
        List.generate(17, (j) {
          final q = p[mirror ? flip[j] : j];
          return PosePoint(
            (mirror ? 1 - q.x : q.x) * scale + shift,
            q.y * scale + shift,
            q.score,
          );
        }),
      );
    }),
    1,
  );
}

void main() {
  for (final rate in [3.68 / 1.37, 4.0, 4.1]) {
    test(
      'fixed endpoints support AB rate $rate within the four-times limit',
      () {
        const duration = 1.37;
        final result = solvePoseAlignment(
          PoseAlignmentRequest(
            a: sequence(1.5, (t) => t),
            b: sequence(6, (t) => t / rate),
            aStart: 0,
            aEnd: duration,
            aRate: 1,
            bStart: 0,
            bEnd: duration * rate,
            bAnchorStart: 0,
            bAnchorEnd: duration * rate,
            searchFraction: 0,
          ),
        );
        if (rate > 4) {
          expect(result, isNull);
        } else {
          expect(result, isNotNull);
          expect(result!.bRate, closeTo(rate, 1e-8));
          expect(result.bStart, 0);
        }
      },
    );
  }
  test(
    'zero radius preserves both B endpoints and derives speed for a short A',
    () {
      final result = solvePoseAlignment(
        PoseAlignmentRequest(
          a: sequence(1.4, (t) => t),
          b: sequence(3, (t) => (t - .5) / 1.2),
          aStart: 0,
          aEnd: 1.3,
          aRate: 1,
          bStart: .5,
          bEnd: 2.06,
          bAnchorStart: .5,
          bAnchorEnd: 2.06,
          searchFraction: 0,
        ),
      );
      expect(result, isNotNull);
      expect(result!.bStart, closeTo(.5, 1e-8));
      expect(result.bRate, closeTo(1.2, 1e-8));
    },
  );
  test('bounded endpoint search never exceeds ten percent of selected B', () {
    final result = solvePoseAlignment(
      PoseAlignmentRequest(
        a: sequence(3, (t) => t),
        b: sequence(6, (t) => t - 1),
        aStart: 0,
        aEnd: 3,
        aRate: 1,
        bStart: .4,
        bEnd: 4.6,
        bAnchorStart: .8,
        bAnchorEnd: 4.2,
        searchFraction: .1,
      ),
    );
    expect(result, isNotNull);
    expect(result!.bStart, inInclusiveRange(.46 - 1e-6, 1.14 + 1e-6));
    expect(
      result.bStart + 3 * result.bRate,
      inInclusiveRange(3.86 - 1e-6, 4.54 + 1e-6),
    );
  });
  test('fixed A with non-default rate recovers B offset and speed', () {
    final a = sequence(8, (t) => t);
    // A starts at source 2, plays at .8; B corresponding instant is 1.4,
    // and B must play at 1.2. Different subject size/location is irrelevant.
    final b = sequence(
      12,
      (t) => 2 + (t - 1.4) * .8 / 1.2,
      scale: .8,
      shift: .1,
    );
    final result = solvePoseAlignment(
      PoseAlignmentRequest(
        a: a,
        b: b,
        aStart: 2,
        aEnd: 6,
        aRate: .8,
        bStart: 0,
        bEnd: 12,
      ),
    );
    expect(result, isNotNull);
    expect(result!.bStart, closeTo(1.4, .07));
    expect(result.bRate, closeTo(1.2, .025));
    expect(result.bStart + 5 * result.bRate, lessThanOrEqualTo(12));
    expect(a.frames.first.seconds, 0);
  });

  test('mirrored matching swaps anatomical left and right', () {
    final result = solvePoseAlignment(
      PoseAlignmentRequest(
        a: sequence(5, (t) => t),
        b: sequence(8, (t) => t - 1, mirror: true),
        aStart: 0,
        aEnd: 5,
        aRate: 1,
        bStart: 0,
        bEnd: 8,
        mirrorB: true,
      ),
    );
    expect(result, isNotNull);
    expect(result!.bStart, closeTo(1, .06));
    expect(result.bRate, closeTo(1, .025));
  });

  test('static or missing pose does not invent an alignment', () {
    final still = sequence(6, (_) => 0);
    expect(
      solvePoseAlignment(
        PoseAlignmentRequest(
          a: still,
          b: still,
          aStart: 0,
          aEnd: 5,
          aRate: 1,
          bStart: 0,
          bEnd: 6,
        ),
      ),
      isNull,
    );
    expect(
      solvePoseAlignment(
        PoseAlignmentRequest(
          a: const PoseSequence([], 1),
          b: still,
          aStart: 0,
          aEnd: 5,
          aRate: 1,
          bStart: 0,
          bEnd: 6,
        ),
      ),
      isNull,
    );
  });

  test('does not accept a short overlap to reduce total error', () {
    expect(
      solvePoseAlignment(
        PoseAlignmentRequest(
          a: sequence(8, (t) => t),
          b: sequence(.4, (t) => t),
          aStart: 0,
          aEnd: 8,
          aRate: 1,
          bStart: 0,
          bEnd: .4,
        ),
      ),
      isNull,
    );
  });

  test(
    'overlay interpolates timestamps and disappears outside analyzed range',
    () {
      final s = sequence(2, (t) => t);
      expect(s.at(.08)!.seconds, .08);
      expect(s.at(5), isNull);
      expect(s.at(-1), isNull);
    },
  );

  test('decoder removes letterbox padding and rejects multiple people', () {
    final values = List.filled(340, 0.0);
    for (var j = 0; j < 17; j++) {
      final offset = j * 20;
      values[offset] = .5;
      values[offset + 1] = .375;
      values[offset + 2] = .9;
      values[offset + 3] = .1;
    }
    final frame = decodeLitePose(values, 1, 2);
    expect(frame.points[11].x, .5);
    expect(frame.points[11].y, .25);
    for (var j = 0; j < 17; j++) {
      final offset = j * 20 + 4;
      values[offset] = .7;
      values[offset + 1] = .4;
      values[offset + 2] = .9;
      values[offset + 3] = 3;
    }
    expect(
      decodeLitePose(values, 1, 2).points.every((p) => p.score == 0),
      isTrue,
    );
  });
}
