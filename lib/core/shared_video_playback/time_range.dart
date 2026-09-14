final class TimeRange {
  TimeRange({required this.start, required this.end})
    : assert(!start.isNegative),
      assert(end >= start);

  final Duration start;
  final Duration end;

  Duration get duration => end - start;

  Duration clamp(Duration position) {
    if (position < start) return start;
    if (position > end) return end;
    return position;
  }

  TimeRange normalizedWithin(Duration mediaDuration) {
    final safeEnd = end > mediaDuration ? mediaDuration : end;
    final safeStart = start > safeEnd ? safeEnd : start;
    return TimeRange(start: safeStart, end: safeEnd);
  }
}
