import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/infrastructure/video_playback/latest_video_seeker.dart';
import 'package:video_player/video_player.dart';

class _SeekPlayer extends VideoPlayerController {
  _SeekPlayer() : super.networkUrl(Uri.parse('https://example.test/video'));

  final firstSeek = Completer<void>();
  final positions = <Duration>[];

  @override
  Future<void> seekTo(Duration position) async {
    positions.add(position);
    if (positions.length == 1) await firstSeek.future;
  }
}

void main() {
  test(
    'disposing a drag drops pending previews and its final commit',
    () async {
      final player = _SeekPlayer();
      final seeker = LatestVideoSeeker(player);
      final first = seeker.seekWhileDragging(const Duration(seconds: 1));
      final pending = seeker.seekWhileDragging(const Duration(seconds: 2));
      final committed = seeker.endUserScrub();
      seeker.dispose();
      player.firstSeek.complete();
      await Future.wait([first, pending, committed]);
      await seeker.seek(const Duration(seconds: 3));
      expect(player.positions, [const Duration(seconds: 1)]);
    },
  );

  test(
    'releasing a drag commits the latest position after an in-flight preview',
    () async {
      final player = _SeekPlayer();
      final seeker = LatestVideoSeeker(player);
      final first = seeker.seekWhileDragging(const Duration(seconds: 1));
      final second = seeker.seekWhileDragging(const Duration(seconds: 2));
      final third = seeker.seekWhileDragging(const Duration(seconds: 3));
      final committed = seeker.endUserScrub();
      player.firstSeek.complete();
      await Future.wait([first, second, third, committed]);
      expect(player.positions, [
        const Duration(seconds: 1),
        const Duration(seconds: 3),
      ]);
      seeker.dispose();
    },
  );

  test(
    'native seek failure reaches the caller and the next seek can recover',
    () async {
      final player = _SeekPlayer();
      final seeker = LatestVideoSeeker(player);
      final failed = seeker.seek(const Duration(seconds: 1));
      final expectation = expectLater(failed, throwsStateError);
      player.firstSeek.completeError(StateError('seek failed'));
      await expectation;
      await seeker.seek(const Duration(seconds: 2));
      expect(player.positions.last, const Duration(seconds: 2));
      seeker.dispose();
    },
  );
}
