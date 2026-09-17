import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/infrastructure/analysis/movenet_analyzer.dart';

void main() {
  test('invalid thread counts are rejected before native setup', () async {
    for (final threads in [0, -1, 5]) {
      await expectLater(
        MoveNetAnalyzer(intraOpThreads: threads).analyze(
          path: '',
          start: 0,
          end: 1,
          aspectRatio: 1,
          onProgress: (_) {},
        ),
        throwsArgumentError,
      );
    }
  });
  test('invalid FPS is rejected before loading native resources', () async {
    for (final fps in [-1, 0, 5, 31, 100]) {
      await expectLater(
        MoveNetAnalyzer().analyze(
          path: '',
          start: 0,
          end: 1,
          aspectRatio: 1,
          samplingFps: fps,
          onProgress: (_) {},
        ),
        throwsArgumentError,
      );
    }
  });
}
