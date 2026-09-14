import 'dart:async';

import 'package:video_player/video_player.dart';

/// Prevents drag gestures from building up a long queue of stale native seeks.
/// While one seek is running, only the newest requested position is retained.
final class LatestVideoSeeker {
  LatestVideoSeeker(this._player);

  final VideoPlayerController _player;
  Duration? _latest;
  Completer<void>? _idle;
  bool _draining = false;
  bool _disposed = false;

  Future<void> seek(Duration position) {
    if (_disposed) return Future.value();
    _latest = position;
    _idle ??= Completer<void>();
    if (!_draining) unawaited(_drain());
    return _idle!.future;
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      while (!_disposed && _latest != null) {
        final target = _latest!;
        _latest = null;
        await _player.seekTo(target);
      }
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
