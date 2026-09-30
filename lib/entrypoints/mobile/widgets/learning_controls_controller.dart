import 'dart:async';

import 'package:flutter/foundation.dart';

/// Keeps practice controls visible during interaction, then frees the canvas.
final class LearningControlsController extends ChangeNotifier {
  Timer? _timer;
  bool _enabled = false;
  bool _visible = true;
  int _hideAfterSeconds = 5;
  final Set<int> _pointers = {};

  bool get visible => _visible;
  int get hideAfterSeconds => _hideAfterSeconds;

  /// Zero leaves controls visible indefinitely.
  set hideAfterSeconds(int seconds) {
    assert(seconds >= 0);
    if (_hideAfterSeconds == seconds) return;
    _hideAfterSeconds = seconds;
    _visible = true;
    _scheduleHide();
    notifyListeners();
  }

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) _pointers.clear();
    show();
  }

  void show() {
    if (!_visible) {
      _visible = true;
      notifyListeners();
    }
    _scheduleHide();
  }

  void pointerDown(int pointer) {
    _pointers.add(pointer);
    _timer?.cancel();
  }

  void pointerUp(int pointer) {
    _pointers.remove(pointer);
    _scheduleHide();
  }

  void _scheduleHide() {
    _timer?.cancel();
    if (!_enabled ||
        !_visible ||
        _pointers.isNotEmpty ||
        _hideAfterSeconds == 0) {
      return;
    }
    _timer = Timer(Duration(seconds: _hideAfterSeconds), () {
      _visible = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
