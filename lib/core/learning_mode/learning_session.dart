import '../shared_video_playback/playback_rate.dart';
import '../shared_video_playback/time_range.dart';
import '../shared_video_playback/video_source.dart';
import 'eight_count_grid.dart';

final class LearningSession {
  const LearningSession({
    required this.video,
    required this.rate,
    required this.loop,
    required this.repeatEnabled,
    required this.restBetweenLoops,
    this.eightCountGrid,
  });

  final VideoSource video;
  final PlaybackRate rate;
  final TimeRange loop;
  final bool repeatEnabled;
  final Duration restBetweenLoops;
  final EightCountGrid? eightCountGrid;

  LearningSession copyWith({
    PlaybackRate? rate,
    TimeRange? loop,
    bool? repeatEnabled,
    Duration? restBetweenLoops,
    EightCountGrid? eightCountGrid,
  }) => LearningSession(
    video: video,
    rate: rate ?? this.rate,
    loop: loop ?? this.loop,
    repeatEnabled: repeatEnabled ?? this.repeatEnabled,
    restBetweenLoops: restBetweenLoops ?? this.restBetweenLoops,
    eightCountGrid: eightCountGrid ?? this.eightCountGrid,
  );
}
