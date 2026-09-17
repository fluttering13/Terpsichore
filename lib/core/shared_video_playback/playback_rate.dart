final class PlaybackRate {
  PlaybackRate(double value, {double upperBound = maximum})
    : value = value.clamp(minimum, upperBound).toDouble();

  PlaybackRate.ab(double value) : this(value, upperBound: abMaximum);

  static const double minimum = 0.1;
  static const double maximum = 2.0;
  static const double abMaximum = 4.0;

  final double value;

  String get label => '${value.toStringAsFixed(2)}x';
}
