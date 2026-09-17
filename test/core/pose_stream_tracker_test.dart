import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';
import 'package:terpsichore/core/ab_analysis/pose_stream_tracker.dart';
import 'package:terpsichore/core/ab_analysis/thunder_crop_tracking.dart';

PoseFrame frame(double time, {double x = .5, double score = .9}) => PoseFrame(
  time,
  List.generate(17, (j) => PosePoint(x, j < 11 ? .4 : .6, score)),
);

void main() {
  test('detect full image then reuse ROI on next sample', () {
    final tracker = PoseStreamTracker(1);
    expect(tracker.cropFor(0), same(thunderFullFrame));
    expect(tracker.observe(frame(0)), isTrue);
    expect(tracker.cropFor(.1).width, lessThan(thunderFullFrame.width));
  });
  test('low confidence resets next sample without retry or filling pose', () {
    final tracker = PoseStreamTracker(1)..observe(frame(0));
    final missing = frame(.1, score: .1);
    expect(tracker.observe(missing), isFalse);
    expect(missing.points.first.score, .1);
    expect(tracker.cropFor(.2), same(thunderFullFrame));
    expect(tracker.observe(frame(.2)), isTrue);
  });
  test('large subject jump discards track and allows reacquisition', () {
    final tracker = PoseStreamTracker(1)..observe(frame(0, x: .2));
    expect(tracker.observe(frame(.1, x: .9)), isFalse);
    expect(tracker.cropFor(.2), same(thunderFullFrame));
    expect(tracker.observe(frame(.2, x: .9)), isTrue);
  });
  test('timestamp gap and backwards seek reset ROI', () {
    for (final next in [-.1, 0.0, .31]) {
      final tracker = PoseStreamTracker(1)..observe(frame(0));
      expect(tracker.cropFor(next), same(thunderFullFrame));
    }
  });
  test('malformed and nonfinite poses cannot create a crop', () {
    for (final pose in [PoseFrame(0, []), frame(0, x: double.nan)]) {
      final tracker = PoseStreamTracker(1);
      expect(tracker.observe(pose), isFalse);
      expect(tracker.cropFor(.1), same(thunderFullFrame));
    }
  });
  test('two streams never share ROI state', () {
    final a = PoseStreamTracker(1)..observe(frame(0));
    final b = PoseStreamTracker(1);
    expect(a.cropFor(.1).width, lessThan(thunderFullFrame.width));
    expect(b.cropFor(.1), same(thunderFullFrame));
  });
}
