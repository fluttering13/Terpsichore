import 'dart:async';

import 'package:video_player/video_player.dart';

/// Confirms native positions advance; isPlaying alone is optimistic in Dart.
/// If one decoder fails to start, restart the pair from the same positions once.
Future<void> startVideoPlaybackTogether(
  Iterable<VideoPlayerController> controllers, {
  required bool Function() isActive,
  Duration startupTimeout = const Duration(milliseconds: 1500),
}) async {
  final players = controllers.toList();
  final starts = players.map((p) => p.value.position).toList();
  try {
    for (var attempt = 0; attempt < 2; attempt++) {
      await waitForVideoPlaybackReady(players);
      if (!isActive()) return;
      await Future.wait(players.map((p) => p.play()));
      final watch = Stopwatch()..start();
      while (watch.elapsed < startupTimeout) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!isActive()) return;
        final positions = await Future.wait(players.map((p) => p.position));
        if (!isActive()) return;
        for (final player in players) {
          if (player.value.hasError) {
            throw StateError(player.value.errorDescription!);
          }
        }
        if (List.generate(players.length, (i) => i).every(
          (i) =>
              positions[i] != null &&
              positions[i]! - starts[i] >=
                  const Duration(milliseconds: 50) *
                      players[i].value.playbackSpeed,
        )) {
          return;
        }
      }
      await Future.wait(players.map((p) => p.pause()));
      if (!isActive()) return;
      if (attempt == 0) {
        await Future.wait([
          for (var i = 0; i < players.length; i++) players[i].seekTo(starts[i]),
        ]);
      }
    }
    throw TimeoutException('The video positions did not advance together.');
  } catch (_) {
    if (isActive()) await Future.wait(players.map((p) => p.pause()));
    rethrow;
  }
}

/// A seek acknowledgement only means the native command was accepted. Keep
/// every track paused until all decoders have finished buffering the new frame.
Future<void> waitForVideoPlaybackReady(
  Iterable<VideoPlayerController> controllers, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final players = controllers.toList();
  final ready = Completer<void>();
  var commandsFlushed = false;
  void check() {
    if (!commandsFlushed || ready.isCompleted) return;
    for (final player in players) {
      if (player.value.hasError) {
        ready.completeError(StateError(player.value.errorDescription!));
        return;
      }
    }
    if (players.every((p) => p.value.isInitialized && !p.value.isBuffering)) {
      ready.complete();
    }
  }

  for (final player in players) {
    player.addListener(check);
  }
  try {
    // Round-trip after the seeks so their queued buffering notifications can
    // reach the controllers before evaluating readiness.
    await Future.wait(players.map((p) => p.position)).timeout(timeout);
    commandsFlushed = true;
    check();
    await ready.future.timeout(timeout);
  } finally {
    for (final player in players) {
      player.removeListener(check);
    }
  }
}
