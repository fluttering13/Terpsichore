import 'package:flutter/material.dart';

import '../../../core/shared_video_playback/time_range.dart';

/// Bounds the displayed trim against a single snapshot of the player duration.
/// Native player errors can temporarily reset that duration to zero. Keep the
/// saved trim intact so it is restored when valid metadata becomes available.
class VideoTrimSlider extends StatelessWidget {
  const VideoTrimSlider({
    required this.trim,
    required this.mediaDuration,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });

  final TimeRange trim;
  final Duration mediaDuration;
  final ValueChanged<RangeValues> onChanged;
  final ValueChanged<RangeValues> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final durationMs = mediaDuration.inMilliseconds;
    final available = durationMs > 0;
    final max = available ? durationMs.toDouble() : 1.0;
    final minimumSpan = max < 100.0 ? max : 100.0;
    var end = available
        ? trim.end.inMilliseconds.toDouble().clamp(0.0, max)
        : 0.0;
    var start = trim.start.inMilliseconds.toDouble().clamp(0.0, end);
    if (available && end - start < minimumSpan) {
      // Repair collapsed saved ranges too, including at either media boundary.
      end = (start + minimumSpan).clamp(0.0, max);
      start = (end - minimumSpan).clamp(0.0, max);
    }
    RangeValues keepPlayable(RangeValues values) {
      if (values.end - values.start >= minimumSpan) return values;
      final movingStart =
          (values.start - start).abs() > (values.end - end).abs();
      return movingStart
          ? RangeValues((values.end - minimumSpan).clamp(0.0, max), values.end)
          : RangeValues(
              values.start,
              (values.start + minimumSpan).clamp(0.0, max),
            );
    }

    return RangeSlider(
      values: RangeValues(start, end),
      max: max,
      onChanged: available ? (values) => onChanged(keepPlayable(values)) : null,
      onChangeEnd: available
          ? (values) => onChangeEnd(keepPlayable(values))
          : null,
    );
  }
}
