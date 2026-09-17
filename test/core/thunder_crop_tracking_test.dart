import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';
import 'package:terpsichore/core/ab_analysis/movenet_processing.dart';
import 'package:terpsichore/core/ab_analysis/rtmpose_processing.dart';
import 'package:terpsichore/core/ab_analysis/thunder_crop_tracking.dart';
import 'package:terpsichore/infrastructure/analysis/pose_crop_worker.dart';

void main() {
  test('missing torso resets to full frame; crop includes observed body', () {
    final points = List.filled(17, const PosePoint(.5, .5, 0));
    expect(thunderNextCrop(PoseFrame(0, points), 1), same(thunderFullFrame));
    for (final j in [5, 6]) {
      points[j] = const PosePoint(.5, .3, .9);
    }
    for (final j in [11, 12]) {
      points[j] = const PosePoint(.5, .5, .9);
    }
    points[15] = const PosePoint(.4, .8, .9);
    final crop = thunderNextCrop(PoseFrame(0, points), 1);
    final half = crop.width * 1.25 / 2;
    expect(half, greaterThanOrEqualTo(.3 * 640));
    expect((crop.left + crop.right) / 2, 320);
    expect(crop.width, lessThan(thunderFullFrame.width));
  });
  test('large confident torso jump is rejected, small motion retained', () {
    PoseFrame frame(double x) =>
        PoseFrame(0, List.filled(17, PosePoint(x, .5, .9)));
    expect(thunderSameSubject(frame(.55), frame(.5), 1), true);
    expect(thunderSameSubject(frame(.9), frame(.1), 1), false);
  });
  test(
    'persistent worker reuses frame, matches direct crop and closes',
    () async {
      final worker = await PoseCropWorker.start();
      final bytes = Uint8List.fromList(
        List.generate(640 * 640 * 3, (i) => i % 251),
      );
      try {
        await expectLater(
          worker.crop(null, thunderFullFrame, 0),
          throwsStateError,
        );
        for (var k = 0; k < 4; k++) {
          final result = await worker.crop(
            k == 0 ? bytes : null,
            thunderFullFrame,
            k,
          );
          expect(
            result.$1,
            orderedEquals(
              prepareRotatedMoveNet((
                PoseCropRequest(bytes, thunderFullFrame, 1),
                k,
              )),
            ),
          );
          expect(result.$2, greaterThan(0));
        }
      } finally {
        worker.close();
      }
      worker.close();
      await expectLater(
        worker.crop(bytes, thunderFullFrame, 0),
        throwsStateError,
      );
    },
  );
}
