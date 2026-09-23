import '../localization/app_text.dart';
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:terpsichore/infrastructure/engagement/easter_egg_service.dart';
import 'package:flutter/material.dart';

final class FrontCameraPanel extends StatefulWidget {
  const FrontCameraPanel({
    required this.recording,
    required this.onRecordingChanged,
    super.key,
  });

  final bool recording;
  final ValueChanged<XFile?> onRecordingChanged;

  @override
  State<FrontCameraPanel> createState() => _FrontCameraPanelState();
}

final class _FrontCameraPanelState extends State<FrontCameraPanel>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  CameraDescription? _description;
  Object? _error;
  bool _switching = false;
  bool _recordingTransition = false;
  bool _mirrorFrontCamera = true;
  int _initializationGeneration = 0;
  Future<void> _cameraOperations = Future<void>.value();
  bool _foreground = true;

  void _logError(String operation, Object error, StackTrace stack) {
    debugPrint('[FrontCameraPanel] $operation: $error\n$stack');
  }

  // Keep native initialization and disposal in order, including initialization
  // that is still waiting for the first camera/microphone permission response.
  Future<void> _enqueue(Future<void> Function() operation) {
    _cameraOperations = _cameraOperations.then((_) => operation()).catchError((
      Object error,
      StackTrace stack,
    ) {
      _logError('camera operation', error, stack);
    });
    return _cameraOperations;
  }

  Future<void> _release(CameraController? controller) async {
    try {
      await controller?.dispose();
    } catch (error, stack) {
      _logError('dispose', error, stack);
    }
  }

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _loadCameras();
  }

  Future<void> _loadCameras() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) throw StateError(appText(context, "找不到可用的鏡頭"));
      final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameras = cameras;
      _description = description;
      if (_foreground) await _initialize(description);
    } catch (error, stack) {
      _logError('load cameras', error, stack);
      if (mounted) {
        setState(() {
          _switching = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _initialize(CameraDescription description) {
    if (!mounted || !_foreground) return Future<void>.value();
    final generation = ++_initializationGeneration;
    final previous = _controller;
    setState(() {
      _controller = null;
      _description = description;
      _switching = true;
      _error = null;
    });
    bool isCurrent() =>
        mounted && _foreground && generation == _initializationGeneration;

    return _enqueue(() async {
      await _release(previous);
      if (!isCurrent()) return;
      final next = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: true,
      );
      try {
        await next.initialize();
        if (!isCurrent()) {
          await _release(next);
          return;
        }
        setState(() {
          _controller = next;
          _switching = false;
          _error = null;
        });
        if (widget.recording) await _syncRecording();
      } catch (error, stack) {
        _logError(
          'initialize generation=$generation current=${isCurrent()}',
          error,
          stack,
        );
        await _release(next);
        if (isCurrent()) {
          setState(() {
            _switching = false;
            _error = error;
          });
        }
      }
    });
  }

  Future<void> _toggleLens() async {
    final controller = _controller;
    final current = _description;
    if (_switching ||
        _recordingTransition ||
        widget.recording ||
        controller == null ||
        controller.value.isRecordingVideo ||
        current == null) {
      return;
    }

    final targetDirection = current.lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    final alternatives = _cameras.where(
      (camera) => camera.name != current.name,
    );
    if (alternatives.isEmpty) return;
    final target = alternatives.firstWhere(
      (camera) => camera.lensDirection == targetDirection,
      orElse: () => alternatives.first,
    );
    await _initialize(target);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint(
      '[FrontCameraPanel] lifecycle=$state generation=$_initializationGeneration',
    );
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    final description = _description;
    if (!foreground) {
      _initializationGeneration++;
      final controller = _controller;
      setState(() {
        _controller = null;
        _error = null;
      });
      unawaited(_enqueue(() => _release(controller)));
    } else if (description != null) {
      unawaited(_initialize(description));
    }
  }

  @override
  void didUpdateWidget(covariant FrontCameraPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recording != widget.recording) {
      unawaited(_syncRecording());
    }
  }

  Future<void> _syncRecording() async {
    if (_recordingTransition) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    _recordingTransition = true;
    if (mounted) setState(() {});
    try {
      if (widget.recording && !controller.value.isRecordingVideo) {
        await controller.startVideoRecording();
        widget.onRecordingChanged(null);
      } else if (!widget.recording && controller.value.isRecordingVideo) {
        final file = await controller.stopVideoRecording();
        widget.onRecordingChanged(file);
      }
    } catch (error, stack) {
      _logError('recording', error, stack);
      if (mounted && identical(controller, _controller)) {
        setState(() => _error = error);
      }
    } finally {
      _recordingTransition = false;
      if (mounted) {
        setState(() {});
        final active = _controller;
        if (active != null &&
            active.value.isInitialized &&
            active.value.isRecordingVideo != widget.recording) {
          unawaited(_syncRecording());
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initializationGeneration++;
    final controller = _controller;
    _controller = null;
    unawaited(_enqueue(() => _release(controller)));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return ColoredBox(
        color: Colors.black38,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              appText(context, "無法開啟鏡頭\n{0}", [appError(context, _error)]),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final description = _description;
    final isFront = description?.lensDirection == CameraLensDirection.front;
    final canSwitch =
        _cameras.any((camera) => camera.name != description?.name) &&
        !_switching &&
        !_recordingTransition &&
        !widget.recording &&
        !controller.value.isRecordingVideo;
    final cameraAspectRatio = controller.value.aspectRatio;
    final displayAspectRatio =
        MediaQuery.orientationOf(context) == Orientation.portrait
        ? 1 / cameraAspectRatio
        : cameraAspectRatio;
    // The camera implementations mirror their front-camera preview already.
    // Apply one extra flip only when the user wants the unmirrored view.
    Widget preview = CameraPreview(controller);
    if (isFront && !_mirrorFrontCamera) {
      preview = Transform.flip(flipX: true, child: preview);
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: displayAspectRatio,
              child: ClipRect(child: preview),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton.filledTonal(
              onPressed: canSwitch ? _toggleLens : null,
              tooltip: isFront
                  ? appText(context, "切換到後鏡頭")
                  : appText(context, "切換到前鏡頭"),
              icon: const Icon(Icons.cameraswitch_outlined),
            ),
          ),
          if (isFront)
            Positioned(
              top: 8,
              right: 56,
              child: IconButton.filledTonal(
                onPressed: () {
                  EasterEggService.instance.mirror();
                  setState(() => _mirrorFrontCamera = !_mirrorFrontCamera);
                },
                tooltip: _mirrorFrontCamera
                    ? appText(context, "取消鏡像")
                    : appText(context, "開啟鏡像"),
                isSelected: _mirrorFrontCamera,
                icon: const Icon(Icons.flip),
              ),
            ),
        ],
      ),
    );
  }
}
