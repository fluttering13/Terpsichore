import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/music_practice/music_loop_policy.dart';
import 'package:terpsichore/core/music_practice/music_practice_session.dart';
import 'package:terpsichore/core/music_practice/music_track_selection.dart';
import 'package:terpsichore/core/music_practice/stem_separation.dart';
import 'package:terpsichore/core/shared_video_playback/playback_rate.dart';
import 'package:terpsichore/core/shared_video_playback/time_range.dart';

void main() {
  test('original and separated stems are mutually exclusive', () {
    final original = MusicTrackSelection.original();
    final drums = original.toggleStem(MusicStem.drums);
    expect(drums.original, isFalse);
    expect(drums.stems, {MusicStem.drums});
    expect(drums.selectOriginal().original, isTrue);
  });

  test('music practice repeats at the selected range with rest', () {
    final session = MusicPracticeSession(
      playbackPath: 'practice.wav',
      duration: const Duration(minutes: 1),
      rate: PlaybackRate(1),
      loop: TimeRange(
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 20),
      ),
      repeatEnabled: true,
      restBetweenLoops: const Duration(seconds: 3),
    );
    final decision = const MusicLoopPolicy().evaluate(
      session,
      const Duration(seconds: 20),
    );
    expect(decision.action, MusicLoopAction.pauseThenRestart);
    expect(decision.seekTo, const Duration(seconds: 10));
    expect(decision.wait, const Duration(seconds: 3));
  });
}
