typedef EggClock = DateTime Function();

/// Session counters are deliberately separate from persisted daily claims.
final class EasterEggEngine {
  EasterEggEngine({
    required this.emit,
    EggClock? clock,
    Map<String, String>? daily,
  }) : clock = clock ?? DateTime.now,
       daily = daily ?? {};

  final void Function(String) emit;
  final EggClock clock;
  final Map<String, String> daily;
  final _shown = <String>{};
  final _counts = <String, int>{};
  final _windows = <String, List<DateTime>>{};
  final _loops = <String, int>{};
  final _segments = <String, String>{};
  final _practice = <String, DateTime>{};
  bool _slowPractice = false;
  DateTime? _homeSince;
  DateTime? _pausedSince;
  String? _pausedFrame;

  String get today {
    final now = clock();
    return '${now.year}-${now.month}-${now.day}';
  }

  void trigger(String id, {bool oncePerDay = false}) {
    if (oncePerDay) {
      if (daily[id] == today) return;
      daily[id] = today;
    } else if (!_shown.add(id)) {
      return;
    }
    emit(id);
  }

  void count(String id, int threshold, {Duration? window}) {
    if (window == null) {
      final value = (_counts[id] ?? 0) + 1;
      _counts[id] = value;
      if (value >= threshold) trigger(id);
    } else {
      final now = clock();
      final events = _windows.putIfAbsent(id, () => []);
      events.removeWhere((at) => now.difference(at) > window);
      events.add(now);
      if (events.length >= threshold) trigger(id);
    }
  }

  void open() {
    _shown.clear();
    _counts.clear();
    _windows.clear();
    _loops.clear();
    _segments.clear();
    _practice.clear();
    _slowPractice = false;
    _homeSince = null;
    clearPause();
    final now = clock();
    if (now.hour < 6) trigger('night', oncePerDay: true);
    if (now.month == 2 && now.day == 29) trigger('leap', oncePerDay: true);
  }

  void home(bool visible, {bool returned = false}) {
    _homeSince = visible ? clock() : null;
    if (!visible) return;
    if (returned) count('return', 11);
    final now = clock();
    if (now.month == 4 && now.day == 1) trigger('april', oncePerDay: true);
  }

  void enterLearning() {
    final now = clock();
    if (now.month == 12 && now.day == 31) trigger('lastBeat', oncePerDay: true);
  }

  void tick() {
    final now = clock();
    if (_homeSince != null &&
        now.difference(_homeSince!) >= const Duration(minutes: 3)) {
      trigger('gaze');
    }
    if (_pausedSince != null &&
        now.difference(_pausedSince!) > const Duration(seconds: 300)) {
      trigger('frozen');
    }
  }

  void clearPause() {
    _pausedSince = null;
    _pausedFrame = null;
  }

  void learningFrame(
    String frame, {
    required bool playing,
    required double rate,
  }) {
    if (playing) {
      clearPause();
      if (rate < 1) _slowPractice = true;
    } else if (_pausedFrame != frame) {
      _pausedFrame = frame;
      _pausedSince = clock();
    }
  }

  void rate(double previous, double next) {
    if (previous == next) return;
    count('speed', 11);
    if (next == 0.25) trigger('quarter');
    if (_slowPractice && previous < 1 && next == 1) {
      trigger('unseal', oncePerDay: true);
      _slowPractice = false;
    }
  }

  void practice(String mode, bool playing, {bool playbackStopped = true}) {
    if (playing) {
      if (_practice.containsKey(mode)) return;
      final now = clock();
      _practice[mode] = now;
      if (now.weekday == DateTime.monday) trigger('monday', oncePerDay: true);
      if (now.weekday == DateTime.friday && now.hour >= 18) trigger('friday');
    } else {
      final start = _practice.remove(mode);
      if (start != null && clock().year > start.year) trigger('newYear');
      if (playbackStopped && (_loops[mode] ?? 0) >= 100) {
        trigger('hundredLoops');
      }
    }
  }

  void segment(String mode, String key) {
    if (_segments[mode] == key) return;
    _segments[mode] = key;
    _loops[mode] = 0;
  }

  void completedLoop(String mode, String key) {
    segment(mode, key);
    _loops[mode] = (_loops[mode] ?? 0) + 1;
  }

  void suspend() {
    for (final mode in _practice.keys.toList()) {
      practice(mode, false, playbackStopped: false);
    }
    _homeSince = null;
    clearPause();
  }
}
