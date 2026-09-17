import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/parallel_pose_jobs.dart';
import 'package:terpsichore/infrastructure/analysis/movenet_analyzer.dart';

void main() {
  test('Android tracking uses Accurate STREAM without Thunder retry gate', () {
    final model = MoveNetAnalyzer.forApp(
      isAndroid: true,
      trackMainPerson: true,
    );
    expect(model.nativeBackend, 'mlkit-accurate');
    expect(model.nativeParallelBackend, isTrue);
    expect(model.multiPersonFiltering, isFalse);
  });

  test('Android tracking off uses Accurate SINGLE_IMAGE', () {
    final model = MoveNetAnalyzer.forApp(
      isAndroid: true,
      trackMainPerson: false,
    );
    expect(model.nativeBackend, 'mlkit-accurate-single');
    expect(model.nativeParallelBackend, isTrue);
    expect(model.multiPersonFiltering, isFalse);
  });

  test('non Android uses INT8 and requested stream tracking', () {
    for (final tracking in [true, false]) {
      final model = MoveNetAnalyzer.forApp(
        isAndroid: false,
        trackMainPerson: tracking,
      );
      expect(model.nativeBackend, 'int8');
      expect(model.nativeParallelBackend, isFalse);
      expect(model.multiPersonFiltering, tracking);
      expect(model.intraOpThreads, 1);
    }
  });

  test('A and B have separate cancellation state', () {
    final a = MoveNetAnalyzer.forApp(isAndroid: true, trackMainPerson: true);
    final b = MoveNetAnalyzer.forApp(isAndroid: true, trackMainPerson: true);
    a.cancelled = true;
    expect(b.cancelled, isFalse);
  });

  test(
    'both jobs start before either completes and results retain A/B order',
    () async {
      final a = Completer<String>();
      final b = Completer<String>();
      final started = <String>[];
      final result = runParallelPoseJobs(
        () {
          started.add('a');
          return a.future;
        },
        () {
          started.add('b');
          return b.future;
        },
      );
      expect(started, ['a', 'b']);
      b.complete('B');
      a.complete('A');
      expect(await result, ['A', 'B']);
    },
  );

  test('failure waits for sibling cleanup before propagating', () async {
    final a = Completer<int>();
    final b = Completer<int>();
    final error = StateError('inference failed');
    var finished = false;
    final result = runParallelPoseJobs(() => a.future, () => b.future);
    final check = expectLater(
      result,
      throwsA(same(error)),
    ).then((_) => finished = true);
    a.completeError(error);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    b.complete(2);
    await check;
  });

  test('synchronous failure still starts and drains sibling', () async {
    final b = Completer<int>();
    var started = false;
    final result = runParallelPoseJobs<int>(
      () => throw StateError('setup'),
      () {
        started = true;
        return b.future;
      },
    );
    final check = expectLater(result, throwsStateError);
    expect(started, isTrue);
    b.complete(2);
    await check;
  });
}
