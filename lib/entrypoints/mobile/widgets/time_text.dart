import 'package:flutter/widgets.dart';

String formatDuration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final tenths = (value.inMilliseconds.remainder(1000) ~/ 100).toString();
  return '$minutes:$seconds.$tenths';
}

final class TimeText extends StatelessWidget {
  const TimeText(this.value, {super.key});

  final Duration value;

  @override
  Widget build(BuildContext context) => Text(
    formatDuration(value),
    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
  );
}
