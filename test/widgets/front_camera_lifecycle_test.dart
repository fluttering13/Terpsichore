import 'dart:async';

// Exercise the camera plugin boundary without requiring hardware.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/front_camera_panel.dart';

class _Camera extends CameraPlatform {
  final events = <String>[];
  late final firstCreate = Completer<void>();
  Completer<void>? release;
  bool deny = false;
  int created = 0;
  final errors = StreamController<CameraErrorEvent>.broadcast();

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings settings,
  ) async {
    final id = ++created;
    events.add('create $id');
    if (id == 1) await firstCreate.future;
    if (deny) throw PlatformException(code: 'CameraAccessDenied');
    return id;
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1280,
          720,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );
  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    events.add('initialize $cameraId');
  }

  @override
  Future<void> dispose(int cameraId) async {
    events.add('dispose $cameraId');
    await release?.future;
    events.add('disposed $cameraId');
  }

  @override
  Widget buildPreview(int cameraId) => Text('preview $cameraId');
}

void main() {
  late _Camera camera;
  late CameraPlatform previous;
  setUp(() {
    previous = CameraPlatform.instance;
    CameraPlatform.instance = camera = _Camera();
  });
  tearDown(() {
    CameraPlatform.instance = previous;
  });

  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FrontCameraPanel(recording: false, onRecordingChanged: (_) {}),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  testWidgets(
    'permission dialog resume waits for old initialization and disposal',
    (tester) async {
      await mount(tester);
      await resume(tester);
      await resume(tester);
      expect(camera.created, 1);
      camera.release = Completer<void>();
      camera.firstCreate.complete();
      await tester.pump();
      expect(camera.events, ['create 1', 'initialize 1', 'dispose 1']);
      expect(find.text('preview 1'), findsNothing);
      camera.release!.complete();
      await tester.pumpAndSettle();
      expect(camera.events, [
        'create 1',
        'initialize 1',
        'dispose 1',
        'disposed 1',
        'create 2',
        'initialize 2',
      ]);
      expect(find.text('preview 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('resuming preview waits for native disposal', (tester) async {
    camera.firstCreate.complete();
    await mount(tester);
    await tester.pumpAndSettle();
    camera.release = Completer<void>();
    await resume(tester);
    expect(camera.created, 1);
    camera.release!.complete();
    await tester.pumpAndSettle();
    expect(
      camera.events.indexOf('disposed 1'),
      lessThan(camera.events.indexOf('create 2')),
    );
    expect(find.text('preview 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'leaving during permission request disposes result without reopening',
    (tester) async {
      await mount(tester);
      await tester.pumpWidget(const SizedBox());
      camera.firstCreate.complete();
      await tester.pumpAndSettle();
      expect(camera.created, 1);
      expect(camera.events.last, 'disposed 1');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('actual permission denial stays visible without retry loop', (
    tester,
  ) async {
    camera.deny = true;
    camera.firstCreate.complete();
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('CameraAccessDenied'), findsOneWidget);
    expect(camera.created, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
