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
    final end = available
        ? trim.end.inMilliseconds.toDouble().clamp(0.0, max)
        : 0.0;
    final start = trim.start.inMilliseconds.toDouble().clamp(0.0, end);
    return RangeSlider(
      values: RangeValues(start, end),
      max: max,
      onChanged: available ? onChanged : null,
      onChangeEnd: available ? onChangeEnd : null,
    );
  }
}
