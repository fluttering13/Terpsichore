import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';
import 'package:terpsichore/core/ab_analysis/pose_sampling.dart';
import 'package:terpsichore/core/ab_analysis/rtmpose_processing.dart';

void main() {
  test('tracker stays with dancer and rejects small bystander after exit', () {
    const dancer = PersonBox(100, 100, 500, 600, .8);
    const moved = PersonBox(130, 100, 530, 600, .7);
    const bystander = PersonBox(150, 300, 200, 400, .99);
    expect(selectPosePerson([bystander, dancer], null), same(dancer));
    expect(selectPosePerson([bystander, moved], dancer), same(moved));
    expect(selectPosePerson([bystander], moved), isNull);
    expect(selectPosePerson([], moved), isNull);
  });
  test('detector uses RGB 0..1 from BGR input', () {
    final bytes = Uint8List(640 * 640 * 3);
    bytes.setRange(0, 3, [10, 20, 30]);
    final tensor = preparePersonDetector(bytes);
    expect(tensor[0], closeTo(30 / 255, 1e-6));
    expect(tensor[640 * 640], closeTo(20 / 255, 1e-6));
    expect(tensor[2 * 640 * 640], closeTo(10 / 255, 1e-6));
  });
  test(
    'SimCC decode maps center back out of letterbox and rejects missing',
    () {
      final sx = List.filled(17 * 384, 0.0);
      final sy = List.filled(17 * 512, 0.0);
      sx[192] = .9;
      sy[256] = .8;
      final frame = decodeRtmPose(
        sx,
        sy,
        const PersonBox(220, 100, 420, 540, .9),
        1,
        9 / 16,
      );
      expect(frame.points[0].x, closeTo(.5, 1e-6));
      expect(frame.points[0].y, closeTo(.5, 1e-6));
      expect(frame.points[0].score, .8);
      expect(frame.points[1].score, 0);
    },
  );
  test('NMS suppresses duplicate detector boxes', () {
    final output = List.filled(56 * 8400, 0.0);
    for (var i = 0; i < 2; i++) {
      output[i] = 320;
      output[8400 + i] = 320;
      output[16800 + i] = 200;
      output[25200 + i] = 300;
      output[33600 + i] = .9 - i * .1;
    }
    expect(decodePersonBoxes(output).length, 1);
  });
  test(
    'sampling is dense for short clips and uncertainty, sparse for stable pose',
    () {
      expect(PoseSamplingPolicy(1.3).shouldInfer(1), isTrue);
      final policy = PoseSamplingPolicy(10);
      expect(policy.shouldInfer(1), isFalse);
      policy.observe(PoseFrame(0, List.filled(17, const PosePoint(0, 0, 0))));
      expect(policy.shouldInfer(1), isTrue);
      policy.observe(
        PoseFrame(.1, List.filled(17, const PosePoint(.5, .5, .9))),
      );
      policy.observe(
        PoseFrame(.2, List.filled(17, const PosePoint(.5, .5, .9))),
      );
      expect(policy.shouldInfer(1), isFalse);
      policy.observe(
        PoseFrame(.3, List.filled(17, const PosePoint(.7, .5, .9))),
      );
      expect(policy.shouldInfer(1), isTrue);
    },
  );
}
