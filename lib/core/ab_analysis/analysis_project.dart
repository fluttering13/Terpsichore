import '../shared_video_playback/playback_rate.dart';
import '../shared_video_playback/time_range.dart';
import '../shared_video_playback/video_source.dart';

enum AnalysisOutput { sideBySide, trackBOnly }

enum AnalysisAudioSource { trackA, trackB, custom, muted }

final class AnalysisCustomAudio {
  AnalysisCustomAudio({
    required this.id,
    required this.path,
    required this.label,
    this.mediaDuration = Duration.zero,
    TimeRange? trim,
    this.timelineStart = Duration.zero,
  }) : trim = trim ?? TimeRange(start: Duration.zero, end: Duration.zero);

  final String id;
  final String path;
  final String label;
  final Duration mediaDuration;
  final TimeRange trim;
  final Duration timelineStart;

  Duration get timelineEnd => timelineStart + trim.duration;

  AnalysisCustomAudio copyWith({
    Duration? mediaDuration,
    TimeRange? trim,
    Duration? timelineStart,
  }) => AnalysisCustomAudio(
    id: id,
    path: path,
    label: label,
    mediaDuration: mediaDuration ?? this.mediaDuration,
    trim: (trim ?? this.trim).normalizedWithin(
      mediaDuration ?? this.mediaDuration,
    ),
    timelineStart: timelineStart ?? this.timelineStart,
  );
}

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
    this.audioSource = AnalysisAudioSource.trackB,
    this.customAudio,
  });

  final AnalysisTrack trackA;
  final AnalysisTrack trackB;
  final AnalysisOutput output;
  final AnalysisAudioSource audioSource;
  final AnalysisCustomAudio? customAudio;

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
