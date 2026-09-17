import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';
import 'package:terpsichore/core/ab_analysis/pose_post_processing.dart';

PoseSequence fixture(
  List<double> times, {
  Set<int> missing = const {},
  bool jump = false,
}) => PoseSequence(
  List.generate(
    times.length,
    (i) => PoseFrame(
      times[i],
      List.generate(
        17,
        (j) => PosePoint(
          jump && i >= 2 ? .9 : .2 + times[i] * .1,
          .3 + times[i] * .1,
          missing.contains(i) ? 0 : .9,
        ),
      ),
    ),
  ),
  1,
);

void main() {
  test('zero and invalid window preserve raw object', () {
    final raw = fixture([0, .1, .2]);
    expect(identical(smoothPoseSequence(raw, 0), raw), isTrue);
    expect(identical(smoothPoseSequence(raw, double.nan), raw), isTrue);
  });
  test('short bounded gap is marked and does not mutate raw confidence', () {
    final raw = fixture([0, .083333, .166667], missing: {1});
    final post = smoothPoseSequence(raw, .3);
    expect(post.frames[1].points[0].inferred, isTrue);
    expect(post.frames[1].points[0].score, .45);
    expect(raw.frames[1].points[0].score, 0);
    expect(post.at(.1)!.points[0].inferred, isTrue);
  });
  test('long and one-sided gaps remain missing', () {
    final post = smoothPoseSequence(
      fixture([0, .1, .2, .3, .4, .5], missing: {0, 2, 3, 5}),
      1,
    );
    for (final i in [0, 2, 3, 5]) {
      expect(post.frames[i].points[0].score, 0);
      expect(post.frames[i].points[0].inferred, isFalse);
    }
  });
  test('irregular timestamps preserve constant velocity without lag', () {
    final raw = fixture([0, .07, .19, .25, .4]);
    final post = smoothPoseSequence(raw, .5);
    for (var i = 0; i < raw.frames.length; i++) {
      expect(post.frames[i].seconds, raw.frames[i].seconds);
      expect(
        post.frames[i].points[0].x,
        closeTo(raw.frames[i].points[0].x, 1e-8),
      );
    }
  });
  test('large torso jumps form a smoothing boundary', () {
    final post = smoothPoseSequence(fixture([0, .08, .16, .24], jump: true), 1);
    expect(post.frames[1].points[0].x, closeTo(.208, 1e-8));
    expect(post.frames[2].points[0].x, .9);
  });
  test('smoothing reduces alternating jitter at the center', () {
    final raw = PoseSequence(
      List.generate(
        7,
        (i) => PoseFrame(
          i / 12,
          List.generate(
            17,
            (_) => PosePoint(.5 + (i.isEven ? .03 : -.03), .5, .9),
          ),
        ),
      ),
      1,
    );
    final post = smoothPoseSequence(raw, .5);
    expect((post.frames[3].points[0].x - .5).abs(), lessThan(.03));
  });
}
