import '../shared_video_playback/time_range.dart';

final class BeatPosition {
  const BeatPosition({required this.eight, required this.beat});

  final int eight;
  final int beat;

  String get label => '第 $eight 個八・第 $beat 拍';
}

final class EightCountGrid {
  EightCountGrid({required this.firstEightStart, required this.firstEightEnd})
    : assert(firstEightEnd > firstEightStart);

  final Duration firstEightStart;
  final Duration firstEightEnd;

  Duration get beatLength => Duration(
    microseconds: (firstEightEnd - firstEightStart).inMicroseconds ~/ 8,
  );

  Duration get eightLength => firstEightEnd - firstEightStart;

  int availableEightCount(Duration mediaDuration) {
    if (mediaDuration <= firstEightStart || eightLength == Duration.zero) {
      return 0;
    }
    final remaining = (mediaDuration - firstEightStart).inMicroseconds;
    final length = eightLength.inMicroseconds;
    return (remaining + length - 1) ~/ length;
  }

  TimeRange rangeForEights({
    required int startEight,
    required int endEight,
    required Duration mediaDuration,
  }) {
    assert(startEight >= 1 && endEight >= startEight);
    final start = timeAt(eight: startEight, beat: 1);
    final nextEightStart = timeAt(eight: endEight + 1, beat: 1);
    return TimeRange(
      start: start,
      end: nextEightStart,
    ).normalizedWithin(mediaDuration);
  }

  BeatPosition? positionAt(Duration position) {
    if (position < firstEightStart || beatLength == Duration.zero) return null;
    final elapsedBeats =
        (position - firstEightStart).inMicroseconds ~/
        beatLength.inMicroseconds;
    return BeatPosition(
      eight: elapsedBeats ~/ 8 + 1,
      beat: elapsedBeats % 8 + 1,
    );
  }

  Duration timeAt({required int eight, required int beat}) {
    assert(eight >= 1 && beat >= 1 && beat <= 8);
    final beatOffset = (eight - 1) * 8 + beat - 1;
    return firstEightStart + beatLength * beatOffset;
  }
}
