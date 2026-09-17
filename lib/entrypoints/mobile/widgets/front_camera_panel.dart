import 'dart:async';

import 'package:camera/camera.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCameras();
  }

  Future<void> _loadCameras() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('找不到可用的鏡頭');
      final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameras = cameras;
      await _initialize(description);
    } catch (error) {
      if (mounted) {
        setState(() {
          _switching = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _initialize(CameraDescription description) async {
    final generation = ++_initializationGeneration;
    final previous = _controller;
    if (mounted) {
      setState(() {
        _controller = null;
        _description = description;
        _switching = true;
        _error = null;
      });
    }
    await previous?.dispose();

    final next = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: true,
    );
    try {
      await next.initialize();
      if (!mounted || generation != _initializationGeneration) {
        await next.dispose();
        return;
      }
      setState(() {
        _controller = next;
        _description = description;
        _switching = false;
        _error = null;
      });
      if (widget.recording) await _syncRecording();
    } catch (error) {
      await next.dispose();
      if (mounted && generation == _initializationGeneration) {
        setState(() {
          _switching = false;
          _error = error;
        });
      }
    }
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
    final description = _description;
    if (state == AppLifecycleState.inactive) {
      _initializationGeneration++;
      final controller = _controller;
      _controller = null;
      unawaited(controller?.dispose());
    } else if (state == AppLifecycleState.resumed && description != null) {
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
    } catch (error) {
      if (mounted) setState(() => _error = error);
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
    _controller?.dispose();
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
            child: Text('無法開啟鏡頭\n$_error', textAlign: TextAlign.center),
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
              tooltip: isFront ? '切換到後鏡頭' : '切換到前鏡頭',
              icon: const Icon(Icons.cameraswitch_outlined),
            ),
          ),
          if (isFront)
            Positioned(
              top: 8,
              right: 56,
              child: IconButton.filledTonal(
                onPressed: () =>
                    setState(() => _mirrorFrontCamera = !_mirrorFrontCamera),
                tooltip: _mirrorFrontCamera ? '取消鏡像' : '開啟鏡像',
                isSelected: _mirrorFrontCamera,
                icon: const Icon(Icons.flip),
              ),
            ),
        ],
      ),
    );
  }
}
