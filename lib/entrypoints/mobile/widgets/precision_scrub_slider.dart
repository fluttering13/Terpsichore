import 'package:flutter/material.dart';

final class PrecisionScrubSlider extends StatefulWidget {
  const PrecisionScrubSlider({
    required this.position,
    required this.duration,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onChanged;
  final ValueChanged<Duration>? onChangeStart;
  final ValueChanged<Duration>? onChangeEnd;

  @override
  State<PrecisionScrubSlider> createState() => _PrecisionScrubSliderState();
}

final class _PrecisionScrubSliderState extends State<PrecisionScrubSlider> {
  static const _fineWindow = Duration(seconds: 2);

  bool _fine = false;
  Duration? _dragWindowCenter;
  Duration? _dragValue;

  @override
  Widget build(BuildContext context) {
    // Avoid a 53-bit shift as a clamp bound: JavaScript bitwise operations
    // cannot represent that bound consistently in a Web debug build.
    final durationMs = widget.duration.inMilliseconds < 1
        ? 1
        : widget.duration.inMilliseconds;
    final positionMs = widget.position.inMilliseconds.clamp(0, durationMs);
    var minimum = 0;
    var maximum = durationMs;

    if (_fine && durationMs > _fineWindow.inMilliseconds) {
      final center = (_dragWindowCenter ?? widget.position).inMilliseconds;
      final half = _fineWindow.inMilliseconds ~/ 2;
      minimum = (center - half).clamp(0, durationMs);
      maximum = (minimum + _fineWindow.inMilliseconds).clamp(0, durationMs);
      minimum = (maximum - _fineWindow.inMilliseconds).clamp(0, durationMs);
    }

    final valueMs = (_dragValue?.inMilliseconds ?? positionMs).clamp(
      minimum,
      maximum,
    );

    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: const EdgeInsets.all(4),
          iconSize: 19,
          tooltip: _fine ? '回到完整時間軸' : '精細拖動（放大目前 2 秒）',
          onPressed: () => setState(() {
            _fine = !_fine;
            _dragWindowCenter = null;
            _dragValue = null;
          }),
          icon: Icon(_fine ? Icons.zoom_out : Icons.zoom_in),
          isSelected: _fine,
        ),
        Expanded(
          child: Slider(
            min: minimum.toDouble(),
            max: maximum.toDouble(),
            value: valueMs.toDouble(),
            onChangeStart: (value) {
              final position = Duration(milliseconds: value.round());
              setState(() {
                _dragWindowCenter = position;
                _dragValue = position;
              });
              widget.onChangeStart?.call(position);
            },
            onChanged: (value) {
              final position = Duration(milliseconds: value.round());
              setState(() => _dragValue = position);
              widget.onChanged(position);
            },
            onChangeEnd: (value) {
              final position = Duration(milliseconds: value.round());
              setState(() {
                _dragWindowCenter = null;
                _dragValue = null;
              });
              widget.onChangeEnd?.call(position);
            },
          ),
        ),
      ],
    );
  }
}
