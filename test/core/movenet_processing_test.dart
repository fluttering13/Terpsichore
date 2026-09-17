import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/movenet_processing.dart';
import 'package:terpsichore/core/ab_analysis/rtmpose_processing.dart';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';

void main() {
  test('direct rotated ROI exactly matches legacy full-image rotation', () {
    final bytes = Uint8List.fromList(
      List.generate(640 * 640 * 3, (i) => (i * 31 + i ~/ 640) % 256),
    );
    for (var k = 0; k < 4; k++) {
      for (final roi in [
        const PersonBox(100, 30, 430, 601, .9),
        const PersonBox(0, 0, 200, 300, .9),
      ]) {
        final legacy = prepareMoveNet(
          PoseCropRequest(rotatePoseImage((bytes, k)), roi, 1),
        );
        final direct = prepareRotatedMoveNet((
          PoseCropRequest(bytes, roi, 1),
          k,
        ));
        expect(direct, orderedEquals(legacy));
      }
    }
  });
  test('low confidence torso triggers full direction recovery', () {
    final points = List.filled(17, const PosePoint(.5, .5, .9));
    expect(isThunderPoseReliable(PoseFrame(0, points)), true);
    points[11] = const PosePoint(.5, .5, .2);
    expect(isThunderPoseReliable(PoseFrame(0, points)), false);
  });
  const box = PersonBox(220, 100, 420, 540, .9);
  test('Thunder is int32 RGB NHWC with an unnormalized byte range', () {
    final bgr = Uint8List(640 * 640 * 3);
    for (var i = 0; i < bgr.length; i += 3) {
      bgr[i] = 10;
      bgr[i + 1] = 20;
      bgr[i + 2] = 30;
    }
    final tensor = prepareMoveNet(PoseCropRequest(bgr, box, 9 / 16));
    expect(tensor, isA<Int32List>());
    expect(tensor.length, 256 * 256 * 3);
    final offset = (128 * 256 + 128) * 3;
    expect(tensor.sublist(offset, offset + 3), [30, 20, 10]);
    expect(tensor.sublist(0, 3), [0, 0, 0]);
  });
  test('normalized y/x decode restores letterbox and preserves confidence', () {
    final values = List<double>.generate(51, (i) => i % 3 == 2 ? .2 : .5);
    final frame = decodeMoveNet(values, box, 1.25, 9 / 16);
    expect(frame.seconds, 1.25);
    expect(frame.points.first.x, closeTo(.5, 1e-6));
    expect(frame.points.first.y, closeTo(.5, 1e-6));
    expect(frame.points.first.score, .2);
    values[0] = double.nan;
    expect(decodeMoveNet(values, box, 0, 9 / 16).points.first.score, 0);
  });
  test('invalid shape is rejected', () {
    expect(() => decodeMoveNet([], box, 0, 1), throwsStateError);
    expect(
      () => prepareMoveNet(PoseCropRequest(Uint8List(1), box, 1)),
      throwsArgumentError,
    );
  });
}
