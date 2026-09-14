final class PlaybackRate {
  PlaybackRate(double value) : value = value.clamp(minimum, maximum).toDouble();

  static const double minimum = 0.1;
  static const double maximum = 2.0;

  final double value;

  String get label => '${value.toStringAsFixed(2)}x';
}
