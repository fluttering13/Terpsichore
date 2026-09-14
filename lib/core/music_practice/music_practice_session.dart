import '../shared_video_playback/playback_rate.dart';
import '../shared_video_playback/time_range.dart';

final class MusicPracticeSession {
  const MusicPracticeSession({
    required this.playbackPath,
    required this.duration,
    required this.rate,
    required this.loop,
    required this.repeatEnabled,
    required this.restBetweenLoops,
  });

  final String playbackPath;
  final Duration duration;
  final PlaybackRate rate;
  final TimeRange loop;
  final bool repeatEnabled;
  final Duration restBetweenLoops;
}
