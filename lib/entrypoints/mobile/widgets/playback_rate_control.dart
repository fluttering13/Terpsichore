import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/shared_video_playback/playback_rate.dart';

final class PlaybackRateControl extends StatelessWidget {
  const PlaybackRateControl({
    required this.value,
    required this.onChanged,
    this.showSlider = true,
    this.maximum = PlaybackRate.maximum,
    super.key,
  });

  final PlaybackRate value;
  final ValueChanged<PlaybackRate> onChanged;
  final bool showSlider;
  final double maximum;

  Future<void> _enterRate(BuildContext context) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) =>
          _PlaybackRateDialog(initialValue: value.value, maximum: maximum),
    );
    if (text == null || !context.mounted) return;
    final number = double.tryParse(text.replaceAll(',', '.'));
    if (number == null ||
        number < PlaybackRate.minimum ||
        !number.isFinite ||
        number > maximum) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('播放速度必須介於 0.10x 和 ${maximum.toStringAsFixed(2)}x'),
        ),
      );
      return;
    }
    onChanged(PlaybackRate(number, upperBound: maximum));
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.speed, size: 20),
      const SizedBox(width: 2),
      TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          minimumSize: const Size(48, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => _enterRate(context),
        child: Text(value.label),
      ),
      if (showSlider)
        Expanded(
          child: Slider(
            value: value.value,
            min: PlaybackRate.minimum,
            max: maximum,
            divisions: ((maximum - PlaybackRate.minimum) / .05).round(),
            onChanged: (next) =>
                onChanged(PlaybackRate(next, upperBound: maximum)),
          ),
        ),
    ],
  );
}

final class _PlaybackRateDialog extends StatefulWidget {
  const _PlaybackRateDialog({
    required this.initialValue,
    required this.maximum,
  });

  final double initialValue;
  final double maximum;

  @override
  State<_PlaybackRateDialog> createState() => _PlaybackRateDialogState();
}

final class _PlaybackRateDialogState extends State<_PlaybackRateDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final text = widget.initialValue.toStringAsFixed(2);
    _controller = TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    title: const Text('輸入播放速度'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        suffixText: 'x',
        helperText: '可輸入 0.10 到 ${widget.maximum.toStringAsFixed(2)}',
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('套用')),
    ],
  );
}
