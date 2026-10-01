import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/pose_3d_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/analysis_gallery.dart';
import 'package:terpsichore/core/ab_analysis/analysis_project.dart';
import 'package:terpsichore/core/ab_analysis/pose_3d.dart';
import 'package:terpsichore/core/shared_video_playback/playback_rate.dart';
import 'package:terpsichore/core/shared_video_playback/time_range.dart';
import 'package:terpsichore/core/shared_video_playback/video_source.dart';
import 'package:terpsichore/infrastructure/analysis/pose_3d_analyzer.dart';
import 'package:terpsichore/infrastructure/analysis/pose_3d_job.dart';
import 'package:terpsichore/infrastructure/analysis/pose_3d_cache.dart';
import 'package:terpsichore/entrypoints/mobile/screens/pose_3d_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('terpsichore/pose3d');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  AnalysisTrack track(String side) => AnalysisTrack(
    source: VideoSource(id: side, path: '/$side.mp4', label: side),
    mediaDuration: const Duration(seconds: 3),
    trim: TimeRange(
      start: const Duration(milliseconds: 200),
      end: const Duration(milliseconds: 700),
    ),
    rate: PlaybackRate(1),
  );
  final project = AnalysisProject(
    trackA: track('A'),
    trackB: track('B'),
    output: AnalysisOutput.sideBySide,
  );
  final points = List<double>.generate(68, (i) => i % 4 == 3 ? 1 : i * .001);
  var created = 0;
  final closed = <String>[];
  final timestamps = <String, List<int>>{};
  Completer<void>? gate;
  var workers = 2;
  var rejectSecond = false;
  var active = 0;
  var peak = 0;
  String? failFrame;
  List<double>? frameResult;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    created = 0;
    closed.clear();
    timestamps.clear();
    gate = null;
    workers = 2;
    rejectSecond = false;
    active = 0;
    peak = 0;
    failFrame = null;
    frameResult = points;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      switch (call.method) {
        case 'configure':
          return {'workers': workers};
        case 'create':
          if (rejectSecond && created == 1 && closed.isEmpty) {
            throw PlatformException(code: 'POSE3D_CAPACITY');
          }
          final id = '${++created}';
          timestamps[id] = [];
          return id;
        case 'frame':
          active++;
          if (active > peak) peak = active;
          timestamps[args['id']]!.add(args['timeUs'] as int);
          if (gate != null) await gate!.future;
          active--;
          if (args['id'] == failFrame) {
            throw PlatformException(code: 'POSE3D_FAILED');
          }
          return frameResult;
        case 'close':
          closed.add(args['id'] as String);
          return null;
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'parallel tracks preserve chronological ordering and close both sessions',
    () async {
      gate = Completer();
      final analyzer = Pose3dAnalyzer();
      final progress = <double>[];
      final future = analyzer.analyze(
        project,
        const Pose3dSettings(fps: 10),
        (p, _) => progress.add(p),
      );
      while (active < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(peak, 2);
      gate!.complete();
      final result = await future;
      expect(closed.length, 2);
      expect(result.a.frames.length, result.b.frames.length);
      for (final values in timestamps.values) {
        expect(values, orderedEquals([...values]..sort()));
        expect(values.first, 200000);
      }
      expect(progress, orderedEquals([...progress]..sort()));
      expect(progress.last, 1);
    },
  );

  test(
    'memory pressure at second model load falls back to sequential processing',
    () async {
      rejectSecond = true;
      await Pose3dAnalyzer().analyze(
        project,
        const Pose3dSettings(fps: 3),
        (_, _) {},
      );
      expect(created, 2);
      expect(closed, ['1', '2']);
      expect(peak, 1);
    },
  );

  test(
    'failed frame waits for both workers before releasing sessions',
    () async {
      gate = Completer();
      failFrame = '1';
      final pending = Pose3dAnalyzer().analyze(
        project,
        const Pose3dSettings(),
        (_, _) {},
      );
      final failed = expectLater(pending, throwsA(isA<PlatformException>()));
      while (active < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(closed, isEmpty);
      gate!.complete();
      await failed;
      expect(active, 0);
      expect(closed, unorderedEquals(['1', '2']));
    },
  );

  test(
    'invalid native frames stay missing instead of reaching rendering',
    () async {
      for (final invalid in [
        null,
        <double>[1, 2, 3],
        [...points]..[0] = double.nan,
      ]) {
        frameResult = invalid;
        final result = await Pose3dAnalyzer().analyze(
          project,
          const Pose3dSettings(fps: 3),
          (_, _) {},
        );
        expect(result.a.frames.every((f) => f.points == null), isTrue);
        expect(result.b.frames.every((f) => f.points == null), isTrue);
      }
      expect(closed.length, 6);
    },
  );

  test('cache write failure retains a completed usable result', () async {
    final job = Pose3dJob(project, const Pose3dSettings(fps: 3));
    job.persist = (_) async => throw const FileSystemException('disk full');
    job.start();
    await job.completion;
    expect(job.status, Pose3dJobStatus.completed);
    expect(job.result, isNotNull);
    expect(job.cacheError, isA<FileSystemException>());
    expect(job.error, isNull);
    job.dispose();
  });

  test(
    'changing settings does not erase results; cancelled rerun retains old result',
    () async {
      final job = Pose3dJob(project, const Pose3dSettings(fps: 3));
      job.start();
      await job.completion;
      final old = job.result!;
      expect(old.settings.fps, 3);
      job.updateSettings(const Pose3dSettings(fps: 10));
      expect(identical(old, job.result), isTrue);
      gate = Completer();
      job.start();
      expect(identical(old, job.result), isTrue);
      while (active < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      job.cancel();
      gate!.complete();
      await job.completion;
      expect(job.status, Pose3dJobStatus.cancelled);
      expect(identical(old, job.result), isTrue);
      gate = null;
      job.start();
      await job.completion;
      expect(job.result!.settings.fps, 10);
      expect(job.result!.a.frames.length, greaterThan(old.a.frames.length));
      job.dispose();
    },
  );

  test(
    'ETA starts after sampling, clears on cancellation and resets on rerun',
    () async {
      gate = Completer();
      final job = Pose3dJob(project, const Pose3dSettings());
      job.start();
      expect(job.estimatedRemaining, isNull);
      while (active < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      final firstBatch = gate!;
      gate = Completer();
      firstBatch.complete();
      while (job.progress == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(job.estimatedRemaining, isNotNull);
      expect(job.estimatedRemaining! > Duration.zero, isTrue);
      job.cancel();
      expect(job.estimatedRemaining, isNull);
      gate!.complete();
      await job.completion;
      gate = Completer();
      job.start();
      expect(job.progress, 0);
      expect(job.estimatedRemaining, isNull);
      job.cancel();
      gate!.complete();
      await job.completion;
      job.dispose();
    },
  );

  testWidgets(
    'back keeps inference alive; explicit cancel on reopened page stops it',
    (tester) async {
      gate = Completer();
      final job = Pose3dJob(project, const Pose3dSettings());
      job.start();
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('A+B')),
        ),
      );
      void open() => nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Pose3dScreen(
            job: job,
            folder: AnalysisGalleryFolder.defaultFolder,
          ),
        ),
      );
      open();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pose3d-cancel')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(job.busy, isTrue);
      expect(closed, isEmpty);
      open();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pose3d-cancel')));
      await tester.pump();
      expect(job.status, Pose3dJobStatus.cancelling);
      gate!.complete();
      await tester.pumpAndSettle();
      expect(job.status, Pose3dJobStatus.cancelled);
      expect(closed.length, 2);
      await tester.pumpWidget(const SizedBox());
      job.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test(
    'cached results survive new jobs, settings changes, and atomic replacement',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pose3d-cache-test-',
      );
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      try {
        final job = Pose3dJob(project, const Pose3dSettings(fps: 3));
        job.start();
        await job.completion;
        await Pose3dCache.save(job.result!);
        final loaded = await Pose3dCache.load(project);
        expect(loaded!.settings.fps, 3);
        job.updateSettings(const Pose3dSettings(fps: 10));
        job.start();
        await job.completion;
        await Pose3dCache.save(job.result!);
        expect((await Pose3dCache.load(project))!.settings.fps, 10);
        job.dispose();
      } finally {
        messenger.setMockMethodCallHandler(paths, null);
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'project results survive other analyses, restart, and media relocation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pose3d-project-test-',
      );
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      AnalysisTrack moved(AnalysisTrack t, String path) => AnalysisTrack(
        source: VideoSource(id: t.source.id, path: path, label: t.source.label),
        mediaDuration: t.mediaDuration,
        trim: t.trim,
        rate: t.rate,
      );
      final saved = AnalysisProject(
        trackA: moved(project.trackA, '/saved/a.mp4'),
        trackB: moved(project.trackB, '/saved/b.mp4'),
        output: AnalysisOutput.sideBySide,
      );
      final other = AnalysisProject(
        trackA: moved(project.trackA, '/other/a.mp4'),
        trackB: moved(project.trackB, '/other/b.mp4'),
        output: AnalysisOutput.sideBySide,
      );
      final manager = Pose3dJobs();
      try {
        // Inference first, project save later moves imported media to durable paths.
        final job = await manager.getOrStart(
          project,
          const Pose3dSettings(fps: 3),
        );
        await job.completion;
        await manager.bindProject('first', project, saved);
        expect(
          (await Pose3dCache.load(
            saved,
            savedProjectId: 'first',
          ))!.settings.fps,
          3,
        );
        // A second project replaces the global recent-result cache.
        final second = await manager.getOrStart(
          other,
          const Pose3dSettings(fps: 10),
          savedProjectId: 'second',
        );
        await second.completion;
        expect(await Pose3dCache.load(saved), isNull);
        final callsBefore = created;
        final originalPaths = await manager.getOrStart(
          project,
          const Pose3dSettings(),
          savedProjectId: 'first',
        );
        expect(originalPaths.status, Pose3dJobStatus.completed);
        expect(
          originalPaths.result!.project.trackA.source.path,
          project.trackA.source.path,
        );
        expect(created, callsBefore);
        final restarted = Pose3dJobs();
        final restored = await restarted.getOrStart(
          saved,
          const Pose3dSettings(fps: 10),
          savedProjectId: 'first',
        );
        expect(restored.status, Pose3dJobStatus.completed);
        expect(restored.result!.settings.fps, 3);
        expect(restored.settings.fps, 10);
        expect(
          created,
          callsBefore,
        ); // Restore must never invoke native inference.
        // A changed trim must not silently reuse the previous timeline's poses.
        final changed = AnalysisProject(
          trackA: saved.trackA.copyWith(
            trim: TimeRange(
              start: const Duration(milliseconds: 300),
              end: const Duration(milliseconds: 700),
            ),
          ),
          trackB: saved.trackB,
          output: AnalysisOutput.sideBySide,
        );
        expect(
          await Pose3dCache.load(changed, savedProjectId: 'first'),
          isNull,
        );
        restored.dispose();
        restarted.dispose();
      } finally {
        manager.current?.dispose();
        manager.dispose();
        messenger.setMockMethodCallHandler(paths, null);
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'saving during inference binds completion; cancelled rerun preserves project result',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pose3d-bind-test-',
      );
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      final manager = Pose3dJobs();
      try {
        gate = Completer();
        final job = await manager.getOrStart(
          project,
          const Pose3dSettings(fps: 3),
        );
        while (active < 2) {
          await Future<void>.delayed(Duration.zero);
        }
        AnalysisTrack moved(AnalysisTrack t) => AnalysisTrack(
          source: VideoSource(
            id: t.source.id,
            path: '/saved${t.source.path}',
            label: t.source.label,
          ),
          mediaDuration: t.mediaDuration,
          trim: t.trim,
          rate: t.rate,
        );
        final saved = AnalysisProject(
          trackA: moved(project.trackA),
          trackB: moved(project.trackB),
          output: AnalysisOutput.sideBySide,
        );
        await manager.bindProject('during', project, saved);
        // Reloading the saved project while its original temporary-path job runs
        // must retain that job's destination binding.
        await manager.bindProject('during', saved, saved);
        gate!.complete();
        await job.completion;
        expect(
          (await Pose3dCache.load(
            saved,
            savedProjectId: 'during',
          ))!.settings.fps,
          3,
        );
        job.updateSettings(const Pose3dSettings(fps: 10));
        gate = Completer();
        job.start();
        while (active < 2) {
          await Future<void>.delayed(Duration.zero);
        }
        job.cancel();
        gate!.complete();
        await job.completion;
        expect(
          (await Pose3dCache.load(
            saved,
            savedProjectId: 'during',
          ))!.settings.fps,
          3,
        );
        // Completed legacy recent results migrate without rerunning the model.
        final restarted = Pose3dJobs();
        await restarted.bindProject('legacy', project, project);
        expect(
          await Pose3dCache.load(project, savedProjectId: 'legacy'),
          isNotNull,
        );
        restarted.dispose();
      } finally {
        manager.current?.dispose();
        manager.dispose();
        messenger.setMockMethodCallHandler(paths, null);
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'projects using identical clips still keep independent inference results',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pose3d-independent-projects-',
      );
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      final manager = Pose3dJobs();
      try {
        final one = await manager.getOrStart(
          project,
          const Pose3dSettings(fps: 3),
          savedProjectId: 'one',
        );
        await one.completion;
        final two = await manager.getOrStart(
          project,
          const Pose3dSettings(fps: 10),
          savedProjectId: 'two',
        );
        expect(identical(one, two), isFalse);
        two.start();
        await two.completion;
        expect(
          (await Pose3dCache.load(
            project,
            savedProjectId: 'one',
          ))!.settings.fps,
          3,
        );
        expect(
          (await Pose3dCache.load(
            project,
            savedProjectId: 'two',
          ))!.settings.fps,
          10,
        );
      } finally {
        manager.current?.dispose();
        manager.dispose();
        messenger.setMockMethodCallHandler(paths, null);
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'result page keeps old result while settings change and rerun is cancelled',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('pose3d-page-settings-'),
      ))!;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      final job = Pose3dJob(project, const Pose3dSettings(fps: 3));
      final sequence = Pose3dSequence([
        Pose3dFrame(0, List.filled(17, const Pose3dPoint(0, 0, 0))),
      ], 3);
      final old = Pose3dComparison(project, job.settings, sequence, sequence);
      job.result = old;
      job.status = Pose3dJobStatus.completed;
      await tester.pumpWidget(
        MaterialApp(
          home: Pose3dScreen(
            job: job,
            folder: AnalysisGalleryFolder.defaultFolder,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is Pose3dPainter,
      );
      Pose3dCamera camera() =>
          (tester.widget<CustomPaint>(viewport).painter! as Pose3dPainter)
              .camera;
      final initial = camera().rotation.rotate(1, 2, 3);
      await tester.drag(viewport, const Offset(80, 40));
      await tester.pump();
      expect(camera().rotation.rotate(1, 2, 3), isNot(initial));
      final afterDrag = camera().rotation;
      final center = tester.getCenter(viewport);
      final finger1 = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      final finger2 = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await tester.pump();
      await finger1.moveBy(const Offset(-30, 0));
      await finger2.moveBy(const Offset(30, 0));
      await tester.pump();
      await finger1.moveBy(const Offset(-20, 0));
      await finger2.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(camera().zoom, greaterThan(1));
      expect(identical(camera().rotation, afterDrag), isTrue);
      await finger1.up();
      await finger2.up();
      await tester.tap(find.byKey(const ValueKey('pose3d-reset-camera')));
      await tester.pump();
      expect(camera().rotation.rotate(1, 2, 3), initial);
      expect(camera().zoom, 1);
      for (final (label, expected) in [
        ('正面', Pose3dCamera(pitch: 0)),
        ('側面', Pose3dCamera(yaw: 1.5707963267948966, pitch: 0)),
        ('俯瞰', Pose3dCamera(pitch: 1.5707963267948966)),
      ]) {
        await tester.tap(find.byKey(ValueKey('pose3d-view-$label')));
        await tester.pump();
        expect(
          camera().rotation.rotate(1, 2, 3),
          expected.rotation.rotate(1, 2, 3),
        );
      }
      expect(find.text('疊合 A/B'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pose3d-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pose3d-page-fps')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 FPS').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('儲存'));
        for (var i = 0; i < 100 && job.settings.fps != 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(job.settings.fps, 10);
      expect(identical(job.result, old), isTrue);
      gate = Completer();
      await tester.tap(find.byKey(const ValueKey('pose3d-rerun')));
      await tester.pumpAndSettle();
      expect(job.busy, isTrue);
      expect(identical(job.result, old), isTrue);
      await tester.tap(find.byKey(const ValueKey('pose3d-cancel')));
      gate!.complete();
      await tester.pumpAndSettle();
      expect(job.status, Pose3dJobStatus.cancelled);
      expect(identical(job.result, old), isTrue);
      await tester.pumpWidget(const SizedBox());
      job.dispose();
      messenger.setMockMethodCallHandler(paths, null);
      await tester.runAsync(() => directory.delete(recursive: true));
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
