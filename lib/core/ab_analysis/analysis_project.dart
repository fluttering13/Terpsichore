import '../shared_video_playback/playback_rate.dart';
import '../shared_video_playback/time_range.dart';
import '../shared_video_playback/video_source.dart';

enum AnalysisOutput { sideBySide, trackBOnly }

final class AnalysisTrack {
  const AnalysisTrack({
    required this.source,
    required this.mediaDuration,
    required this.trim,
    required this.rate,
  });

  final VideoSource source;
  final Duration mediaDuration;
  final TimeRange trim;
  final PlaybackRate rate;

  Duration get effectiveDuration => Duration(
    microseconds: (trim.duration.inMicroseconds / rate.value).round(),
  );

  AnalysisTrack copyWith({TimeRange? trim, PlaybackRate? rate}) =>
      AnalysisTrack(
        source: source,
        mediaDuration: mediaDuration,
        trim: (trim ?? this.trim).normalizedWithin(mediaDuration),
        rate: rate ?? this.rate,
      );
}

final class AnalysisProject {
  const AnalysisProject({
    required this.trackA,
    required this.trackB,
    required this.output,
  });

  final AnalysisTrack trackA;
  final AnalysisTrack trackB;
  final AnalysisOutput output;

  Duration get sharedTimelineDuration =>
      trackA.effectiveDuration < trackB.effectiveDuration
      ? trackA.effectiveDuration
      : trackB.effectiveDuration;

  Duration sourcePositionAt(AnalysisTrack track, double progress) {
    final safeProgress = progress.clamp(0.0, 1.0);
    final sharedElapsed = sharedTimelineDuration * safeProgress;
    final sourceOffset = sharedElapsed * track.rate.value;
    return track.trim.clamp(track.trim.start + sourceOffset);
  }
}
