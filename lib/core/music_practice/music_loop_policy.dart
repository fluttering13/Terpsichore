import 'music_practice_session.dart';

int visibleMusicRestCountdownSeconds(Duration remaining) {
  if (remaining <= Duration.zero) return 0;
  return (remaining.inMilliseconds + 999) ~/ 1000;
}

enum MusicLoopAction { none, seekAndPlay, pauseThenRestart }

final class MusicLoopDecision {
  const MusicLoopDecision._(this.action, this.seekTo, this.wait);

  const MusicLoopDecision.none()
    : this._(MusicLoopAction.none, null, Duration.zero);

  const MusicLoopDecision.seekAndPlay(Duration position)
    : this._(MusicLoopAction.seekAndPlay, position, Duration.zero);

  const MusicLoopDecision.pauseThenRestart(Duration position, Duration wait)
    : this._(MusicLoopAction.pauseThenRestart, position, wait);

  final MusicLoopAction action;
  final Duration? seekTo;
  final Duration wait;
}

final class MusicLoopPolicy {
  const MusicLoopPolicy();

  MusicLoopDecision evaluate(MusicPracticeSession session, Duration position) {
    if (!session.repeatEnabled || position < session.loop.end) {
      return const MusicLoopDecision.none();
    }
    if (session.restBetweenLoops == Duration.zero) {
      return MusicLoopDecision.seekAndPlay(session.loop.start);
    }
    return MusicLoopDecision.pauseThenRestart(
      session.loop.start,
      session.restBetweenLoops,
    );
  }
}
