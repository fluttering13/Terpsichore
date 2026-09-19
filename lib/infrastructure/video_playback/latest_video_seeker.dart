import 'dart:async';

import 'package:video_player/video_player.dart';
import 'package:video_player_android/video_player_android.dart';

/// Prevents drag gestures from building up a long queue of stale native seeks.
/// While one seek is running, only the newest requested position is retained.
final class LatestVideoSeeker {
  LatestVideoSeeker(this._player);

  final VideoPlayerController _player;
  ({Duration position, bool userScrub})? _latest;
  Duration? _lastRequestedPosition;
  Completer<void>? _idle;
  bool _draining = false;
  bool _disposed = false;

  Future<void> seek(Duration position) => _enqueue(position, userScrub: false);

  Future<void> seekWhileDragging(Duration position) =>
      _enqueue(position, userScrub: true);

  Future<void> endUserScrub() => _lastRequestedPosition == null
      ? Future.value()
      : seek(_lastRequestedPosition!);

  Future<void> _enqueue(Duration position, {required bool userScrub}) {
    if (_disposed) return Future.value();
    _lastRequestedPosition = position;
    _latest = (position: position, userScrub: userScrub);
    _idle ??= Completer<void>();
    final result = _idle!.future;
    if (!_draining) unawaited(_drain());
    return result;
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      while (!_disposed && _latest != null) {
        final target = _latest!;
        _latest = null;
        if (target.userScrub) {
          await duringUserVideoScrub(() => _player.seekTo(target.position));
        } else {
          await _player.seekTo(target.position);
        }
      }
    } catch (error, stack) {
      _latest = null;
      _idle?.completeError(error, stack);
    } finally {
      _draining = false;
      final idle = _idle;
      _idle = null;
      if (idle != null && !idle.isCompleted) idle.complete();
    }
  }

  void dispose() {
    _disposed = true;
    _latest = null;
  }
}
