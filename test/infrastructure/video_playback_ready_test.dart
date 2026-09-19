import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/infrastructure/video_playback/video_playback_ready.dart';
import 'package:video_player/video_player.dart';

class _Player extends VideoPlayerController {
  _Player() : super.networkUrl(Uri.parse('https://example.test/video')) {
    value = const VideoPlayerValue(
      duration: Duration(seconds: 20),
      isInitialized: true,
      isBuffering: true,
    );
  }

  @override
  Future<Duration?> get position async => value.position;

  bool get listening => hasListeners;

  void ready() => value = value.copyWith(isBuffering: false);
}

class _StartingPlayer extends _Player {
  _StartingPlayer(
    this.stalledAttempts, {
    Duration start = const Duration(seconds: 6),
    double speed = 1,
  }) {
    ready();
    value = value.copyWith(position: start, playbackSpeed: speed);
  }

  final int stalledAttempts;
  int plays = 0;
  final seeks = <Duration>[];

  @override
  Future<void> play() async {
    plays++;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> seekTo(Duration target) async {
    seeks.add(target);
    value = value.copyWith(position: target);
  }

  @override
  Future<Duration?> get position async {
    if (value.isPlaying && plays > stalledAttempts) {
      value = value.copyWith(
        position:
            value.position +
            const Duration(milliseconds: 100) * value.playbackSpeed,
      );
    }
    return value.position;
  }
}

void main() {
  test(
    'optimistic playing state with frozen A restarts both from their original positions',
    () async {
      const aStart = Duration(milliseconds: 6104);
      const bStart = Duration(milliseconds: 5740);
      final a = _StartingPlayer(1, start: aStart);
      final b = _StartingPlayer(0, start: bStart, speed: .385);
      await startVideoPlaybackTogether(
        [a, b],
        isActive: () => true,
        startupTimeout: const Duration(milliseconds: 80),
      );
      expect(a.plays, 2);
      expect(b.plays, 2);
      expect(a.seeks, [aStart]);
      expect(b.seeks, [bStart]);
      expect(a.value.position, greaterThan(aStart));
      expect(b.value.position, greaterThan(bStart));
      expect(b.value.playbackSpeed, .385);
    },
  );

  test('persistent frozen A stops both players after one recovery', () async {
    final a = _StartingPlayer(99);
    final b = _StartingPlayer(0);
    await expectLater(
      startVideoPlaybackTogether(
        [a, b],
        isActive: () => true,
        startupTimeout: const Duration(milliseconds: 80),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(a.plays, 2);
    expect(b.plays, 2);
    expect(a.value.isPlaying, isFalse);
    expect(b.value.isPlaying, isFalse);
  });

  test('cancelled preparation cannot restart playback', () async {
    final a = _StartingPlayer(0);
    await startVideoPlaybackTogether([a], isActive: () => false);
    expect(a.plays, 0);
  });
  test(
    'a faster B cannot release the shared start before A is ready',
    () async {
      final a = _Player();
      final b = _Player();
      var completed = false;
      final waiting = waitForVideoPlaybackReady([
        a,
        b,
      ]).then((_) => completed = true);
      b.ready();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      a.ready();
      await waiting;
      expect(completed, isTrue);
      expect(a.value.isPlaying, isFalse);
      expect(b.value.isPlaying, isFalse);
      expect(a.listening, isFalse);
      expect(b.listening, isFalse);
    },
  );

  test('already prepared tracks need no buffering transition', () async {
    final a = _Player()..ready();
    await waitForVideoPlaybackReady([a]);
    expect(a.listening, isFalse);
  });

  test('buffering timeout cleans up listeners', () async {
    final a = _Player();
    await expectLater(
      waitForVideoPlaybackReady([a], timeout: const Duration(milliseconds: 10)),
      throwsA(isA<TimeoutException>()),
    );
    expect(a.listening, isFalse);
  });

  test('decoder failure does not release the shared start', () async {
    final a = _Player();
    final waiting = waitForVideoPlaybackReady([a]);
    a.value = VideoPlayerValue.erroneous('decode failed');
    await expectLater(waiting, throwsStateError);
    expect(a.listening, isFalse);
  });
}
