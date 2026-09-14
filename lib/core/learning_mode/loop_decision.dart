import 'learning_session.dart';

int visibleRestCountdownSeconds(Duration remaining) {
  if (remaining <= Duration.zero) return 0;
  return (remaining.inMilliseconds + 999) ~/ 1000;
}

enum LoopActionType { none, seekAndPlay, pauseThenRestart }

final class LoopDecision {
  const LoopDecision._(this.type, this.seekTo, this.wait);

  const LoopDecision.none() : this._(LoopActionType.none, null, Duration.zero);

  const LoopDecision.seekAndPlay(Duration position)
    : this._(LoopActionType.seekAndPlay, position, Duration.zero);

  const LoopDecision.pauseThenRestart(Duration position, Duration wait)
    : this._(LoopActionType.pauseThenRestart, position, wait);

  final LoopActionType type;
  final Duration? seekTo;
  final Duration wait;
}

final class LearningLoopPolicy {
  const LearningLoopPolicy();

  LoopDecision evaluate(LearningSession session, Duration position) {
    if (position < session.loop.end) return const LoopDecision.none();
    if (!session.repeatEnabled) return const LoopDecision.none();
    if (session.restBetweenLoops == Duration.zero) {
      return LoopDecision.seekAndPlay(session.loop.start);
    }
    return LoopDecision.pauseThenRestart(
      session.loop.start,
      session.restBetweenLoops,
    );
  }
}
