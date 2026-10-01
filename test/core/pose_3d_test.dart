import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/analysis_project.dart';
import 'package:terpsichore/core/ab_analysis/pose_3d.dart';
import 'package:terpsichore/core/shared_video_playback/playback_rate.dart';
import 'package:terpsichore/core/shared_video_playback/time_range.dart';
import 'package:terpsichore/core/shared_video_playback/video_source.dart';

void main() {
  test('ETA uses combined throughput and handles startup and completion', () {
    expect(estimatePose3dRemaining(0, const Duration(seconds: 30)), isNull);
    expect(estimatePose3dRemaining(.25, Duration.zero), isNull);
    expect(
      estimatePose3dRemaining(.25, const Duration(seconds: 20)),
      const Duration(seconds: 60),
    );
    expect(
      estimatePose3dRemaining(.5, const Duration(seconds: 45)),
      const Duration(seconds: 45),
    );
    expect(
      estimatePose3dRemaining(1, const Duration(seconds: 80)),
      Duration.zero,
    );
  });
  AnalysisTrack track(String id, int start, int end, double rate) =>
      AnalysisTrack(
        source: VideoSource(id: id, path: '/$id.mp4', label: id),
        mediaDuration: const Duration(seconds: 30),
        trim: TimeRange(
          start: Duration(seconds: start),
          end: Duration(seconds: end),
        ),
        rate: PlaybackRate.ab(rate),
      );
  final project = AnalysisProject(
    trackA: track('a', 3, 13, 2),
    trackB: track('b', 7, 11, .5),
    output: AnalysisOutput.sideBySide,
  );

  test(
    'inference samples adjusted common time with independent trim and speed',
    () {
      final times = pose3dSampleTimes(project, 2);
      expect(project.sharedTimelineDuration, const Duration(seconds: 5));
      expect(times.take(3), [0, .5, 1]);
      expect(
        project.sourcePositionAt(project.trackA, times[2] / 5),
        const Duration(seconds: 5),
      );
      expect(
        project.sourcePositionAt(project.trackB, times[2] / 5),
        const Duration(milliseconds: 7500),
      );
      expect(times.last, closeTo(4.999, .00001));
      expect(times.every((t) => t < 5), isTrue);
    },
  );

  test(
    'interpolation repairs a bounded missing sample without changing raw results',
    () {
      List<Pose3dPoint> points(double x) =>
          List.filled(17, Pose3dPoint(x, 0, 1));
      final sequence = Pose3dSequence([
        Pose3dFrame(0, points(0)),
        Pose3dFrame(.1, points(2)),
        const Pose3dFrame(.2, null),
        Pose3dFrame(.3, points(6)),
      ], 10);
      expect(sequence.at(.05, interpolate: true).points!.first.x, 1);
      expect(sequence.at(.05, interpolate: true).interpolated, isTrue);
      expect(sequence.at(.05, interpolate: false).points!.first.x, 0);
      expect(
        sequence.at(.15, interpolate: true).points!.first.x,
        closeTo(3, 1e-6),
      );
      expect(
        sequence.at(.2, interpolate: true).points!.first.x,
        closeTo(4, 1e-6),
      );
      expect(sequence.at(.2, interpolate: true).interpolated, isTrue);
      expect(
        sequence.at(.25, interpolate: true).points!.first.x,
        closeTo(5, 1e-6),
      );
      expect(sequence.at(.2, interpolate: false).points, isNull);
      expect(sequence.frames[2].points, isNull);
      expect(sequence.at(.3, interpolate: true).points!.first.x, 6);
    },
  );

  test('5 FPS double dropout stays visible throughout 30 FPS playback', () {
    final sequence = Pose3dSequence([
      Pose3dFrame(2.2, List.filled(17, const Pose3dPoint(0, 0, 0))),
      const Pose3dFrame(2.4, null),
      const Pose3dFrame(2.6, null),
      Pose3dFrame(2.8, List.filled(17, const Pose3dPoint(6, 0, 0))),
    ], 5);
    for (var frame = 66; frame <= 84; frame++) {
      final t = frame / 30;
      final pose = sequence.at(t, interpolate: true);
      expect(pose.points, isNotNull, reason: 'Blank at $t');
      expect(pose.points!.first.x, closeTo((t - 2.2) * 10, 1e-6));
    }
    for (final t in [2.4, 2.6]) {
      expect(sequence.at(t, interpolate: false).points, isNull);
    }
    expect(sequence.frames.where((f) => f.points == null).length, 2);

    final longer = Pose3dSequence([
      Pose3dFrame(0, List.filled(17, const Pose3dPoint(0, 0, 0))),
      const Pose3dFrame(.2, null),
      const Pose3dFrame(.4, null),
      Pose3dFrame(.601, List.filled(17, const Pose3dPoint(6, 0, 0))),
    ], 5);
    expect(longer.at(.3, interpolate: true).points, isNull);
  });

  test('gap repair respects duration, count, and boundaries', () {
    List<Pose3dPoint> points(double x) => List.filled(17, Pose3dPoint(x, 0, 0));
    final example = Pose3dSequence([
      Pose3dFrame(2.6, points(0)),
      const Pose3dFrame(2.8, null),
      Pose3dFrame(3, points(2)),
    ], 5);
    for (var frame = 79; frame < 90; frame++) {
      expect(example.at(frame / 30, interpolate: true).points, isNotNull);
    }
    expect(
      example.at(2.8, interpolate: true).points!.first.x,
      closeTo(1, 1e-6),
    );
    final two = Pose3dSequence([
      Pose3dFrame(0, points(0)),
      const Pose3dFrame(.1, null),
      const Pose3dFrame(.2, null),
      Pose3dFrame(.3, points(3)),
    ], 10);
    expect(two.at(.2, interpolate: true).points!.first.x, closeTo(2, 1e-6));
    final three = Pose3dSequence([
      Pose3dFrame(0, points(0)),
      const Pose3dFrame(.1, null),
      const Pose3dFrame(.2, null),
      const Pose3dFrame(.3, null),
      Pose3dFrame(.4, points(4)),
    ], 10);
    expect(three.at(.2, interpolate: true).points, isNull);
    final slow = Pose3dSequence([
      Pose3dFrame(0, points(0)),
      const Pose3dFrame(1, null),
      Pose3dFrame(2, points(2)),
    ], 1);
    expect(slow.at(1, interpolate: true).points, isNull);
    final edges = Pose3dSequence([
      const Pose3dFrame(0, null),
      Pose3dFrame(.1, points(1)),
      const Pose3dFrame(.2, null),
    ], 10);
    expect(edges.at(0, interpolate: true).points, isNull);
    expect(edges.at(.2, interpolate: true).points, isNull);
  });

  test('defaults and retired Heavy settings migrate to NLF at 10 FPS', () {
    final defaults = Pose3dSettings.fromJson(null);
    expect(defaults.model, Pose3dModel.nlfInt8);
    expect(defaults.fps, 10);
    expect(
      Pose3dSettings.fromJson({'model': 'mediaPipeHeavy', 'fps': 12}).fps,
      10,
    );
    expect(defaults.interpolate, isTrue);
    const nlf = Pose3dSettings(
      model: Pose3dModel.nlfInt8,
      fps: 3,
      interpolate: false,
    );
    final restored = Pose3dSettings.fromJson(nlf.toJson());
    expect(restored.model, nlf.model);
    expect(restored.fps, 3);
    expect(restored.interpolate, isFalse);
    expect(Pose3dSettings.fromJson({'fps': 999, 'model': 'unknown'}).fps, 10);
  });
}
