import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/learning_mode/learning_session.dart';
import 'package:terpsichore/core/learning_mode/loop_decision.dart';
import 'package:terpsichore/core/shared_video_playback/playback_rate.dart';
import 'package:terpsichore/core/shared_video_playback/time_range.dart';
import 'package:terpsichore/core/shared_video_playback/video_source.dart';

void main() {
  test('rounds the visible rest countdown up to whole seconds', () {
    expect(visibleRestCountdownSeconds(const Duration(milliseconds: 2500)), 3);
    expect(visibleRestCountdownSeconds(const Duration(seconds: 2)), 2);
    expect(visibleRestCountdownSeconds(const Duration(milliseconds: 1)), 1);
    expect(visibleRestCountdownSeconds(Duration.zero), 0);
  });

  const source = VideoSource(id: 'v', path: '/v.mp4', label: 'v');

  LearningSession session({Duration rest = Duration.zero}) => LearningSession(
    video: source,
    rate: PlaybackRate(0.5),
    loop: TimeRange(start: Duration(seconds: 3), end: Duration(seconds: 7)),
    repeatEnabled: true,
    restBetweenLoops: rest,
  );

  test('restarts immediately when loop ends without rest', () {
    final result = const LearningLoopPolicy().evaluate(
      session(),
      const Duration(seconds: 7),
    );
    expect(result.type, LoopActionType.seekAndPlay);
    expect(result.seekTo, const Duration(seconds: 3));
  });

  test('requests a pause before restarting when rest is configured', () {
    final result = const LearningLoopPolicy().evaluate(
      session(rest: const Duration(seconds: 5)),
      const Duration(seconds: 7),
    );
    expect(result.type, LoopActionType.pauseThenRestart);
    expect(result.wait, const Duration(seconds: 5));
  });
}
