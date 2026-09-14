import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/analysis_project.dart';
import 'package:terpsichore/core/shared_video_playback/playback_rate.dart';
import 'package:terpsichore/core/shared_video_playback/time_range.dart';
import 'package:terpsichore/core/shared_video_playback/video_source.dart';

void main() {
  AnalysisTrack track(String id, double rate) => AnalysisTrack(
    source: VideoSource(id: id, path: '/$id.mp4', label: id),
    mediaDuration: const Duration(seconds: 30),
    trim: TimeRange(start: Duration(seconds: 5), end: Duration(seconds: 15)),
    rate: PlaybackRate(rate),
  );

  test('speed changes the effective comparison duration', () {
    expect(track('a', 0.5).effectiveDuration, const Duration(seconds: 20));
    expect(track('b', 2).effectiveDuration, const Duration(seconds: 5));
  });

  test('shared progress maps into each trimmed source range', () {
    final a = track('a', 1);
    final project = AnalysisProject(
      trackA: a,
      trackB: track('b', 1),
      output: AnalysisOutput.sideBySide,
    );
    expect(project.sourcePositionAt(a, 0.5), const Duration(seconds: 10));
  });

  test('shared playback ends at the shorter effective track', () {
    final project = AnalysisProject(
      trackA: track('a', 0.5),
      trackB: track('b', 2),
      output: AnalysisOutput.sideBySide,
    );

    expect(project.sharedTimelineDuration, const Duration(seconds: 5));
    expect(
      project.sourcePositionAt(project.trackA, 1),
      const Duration(milliseconds: 7500),
    );
    expect(
      project.sourcePositionAt(project.trackB, 1),
      const Duration(seconds: 15),
    );
  });
}
