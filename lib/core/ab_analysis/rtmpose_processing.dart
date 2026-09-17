import 'dart:math' as math;
import 'dart:typed_data';

import 'pose_alignment.dart';

/// Coordinates are pixels in the 640x640 letterboxed detector image.
final class PersonBox {
  const PersonBox(this.left, this.top, this.right, this.bottom, this.score);
  final double left, top, right, bottom, score;
  double get width => right - left;
  double get height => bottom - top;
  double get area => width * height;
  double iou(PersonBox other) {
    final intersection =
        math.max(
          0.0,
          math.min(right, other.right) - math.max(left, other.left),
        ) *
        math.max(
          0.0,
          math.min(bottom, other.bottom) - math.max(top, other.top),
        );
    return intersection / math.max(1.0, area + other.area - intersection);
  }
}

/// YOLO11s-Pose's first five channels contain the person detector output.
List<PersonBox> decodePersonBoxes(List<double> output) {
  const n = 8400;
  if (output.length != 56 * n) throw StateError('人物定位模型輸出不相容');
  final candidates = <PersonBox>[];
  for (var i = 0; i < n; i++) {
    final score = output[4 * n + i];
    final x = output[i], y = output[n + i];
    final w = output[2 * n + i], h = output[3 * n + i];
    if (![score, x, y, w, h].every((v) => v.isFinite) ||
        score < .25 ||
        w <= 1 ||
        h <= 1) {
      continue;
    }
    candidates.add(
      PersonBox(
        (x - w / 2).clamp(0.0, 640.0),
        (y - h / 2).clamp(0.0, 640.0),
        (x + w / 2).clamp(0.0, 640.0),
        (y + h / 2).clamp(0.0, 640.0),
        score,
      ),
    );
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final kept = <PersonBox>[];
  for (final box in candidates.take(300)) {
    if (box.area > 1 && !kept.any((p) => p.iou(box) > .45)) kept.add(box);
  }
  return kept;
}

/// Lock onto the initial largest person. Do not silently jump to a much
/// smaller bystander when the dancer exits. Keep the last box on a miss.
PersonBox? selectPosePerson(List<PersonBox> boxes, PersonBox? previous) {
  if (boxes.isEmpty) return null;
  if (previous == null) return boxes.reduce((a, b) => a.area > b.area ? a : b);
  final compatible = boxes
      .where(
        (b) =>
            b.area >= previous.area * .35 &&
            b.area <= previous.area * 3 &&
            b.iou(previous) >= .1,
      )
      .toList();
  if (compatible.isEmpty) return null;
  return compatible.reduce((a, b) => a.iou(previous) > b.iou(previous) ? a : b);
}

Float32List preparePersonDetector(Uint8List bgr) {
  const pixels = 640 * 640;
  if (bgr.length != pixels * 3) throw ArgumentError('影格尺寸不相容');
  final tensor = Float32List(pixels * 3);
  for (var i = 0; i < pixels; i++) {
    tensor[i] = bgr[i * 3 + 2] / 255;
    tensor[pixels + i] = bgr[i * 3 + 1] / 255;
    tensor[2 * pixels + i] = bgr[i * 3] / 255;
  }
  return tensor;
}

final class PoseCropRequest {
  const PoseCropRequest(this.bgr, this.box, this.aspectRatio);
  final Uint8List bgr;
  final PersonBox box;
  final double aspectRatio;
}

/// RTMPose padding=1.25, aspect=192/256. BGR mean/std follows the
/// OpenMMLab ONNX example used in the candidate benchmark.
Float32List prepareRtmPose(PoseCropRequest request) {
  final box = request.box;
  final scaleX = math.max(box.width, box.height * .75) * 1.25;
  final scaleY = scaleX / .75;
  final cx = (box.left + box.right) / 2;
  final cy = (box.top + box.bottom) / 2;
  final aspect = request.aspectRatio;
  final contentW = aspect >= 1 ? 640.0 : (640 * aspect).floorToDouble();
  final contentH = aspect >= 1 ? (640 / aspect).floorToDouble() : 640.0;
  final padX = ((640 - contentW) / 2).floorToDouble();
  final padY = ((640 - contentH) / 2).floorToDouble();
  const mean = [123.675, 116.28, 103.53];
  const std = [58.395, 57.12, 57.375];
  const pixels = 192 * 256;
  final result = Float32List(pixels * 3);
  double sample(int x, int y, int c) {
    if (x < padX || x >= padX + contentW || y < padY || y >= padY + contentH) {
      return 0;
    }
    return request.bgr[(y * 640 + x) * 3 + c].toDouble();
  }

  for (var y = 0; y < 256; y++) {
    final sy = cy + (y / 256 - .5) * scaleY;
    final iy = sy.floor(), fy = sy - sy.floor();
    for (var x = 0; x < 192; x++) {
      final sx = cx + (x / 192 - .5) * scaleX;
      final ix = sx.floor(), fx = sx - sx.floor();
      for (var c = 0; c < 3; c++) {
        final value =
            sample(ix, iy, c) * (1 - fx) * (1 - fy) +
            sample(ix + 1, iy, c) * fx * (1 - fy) +
            sample(ix, iy + 1, c) * (1 - fx) * fy +
            sample(ix + 1, iy + 1, c) * fx * fy;
        result[c * pixels + y * 192 + x] = (value - mean[c]) / std[c];
      }
    }
  }
  return result;
}

PoseFrame decodeRtmPose(
  List<double> sx,
  List<double> sy,
  PersonBox box,
  double seconds,
  double aspect,
) {
  if (sx.length != 17 * 384 || sy.length != 17 * 512) {
    throw StateError('RTMPose-S 關節輸出不相容');
  }
  final scaleX = math.max(box.width, box.height * .75) * 1.25;
  final scaleY = scaleX / .75;
  final cw = aspect >= 1 ? 640.0 : (640 * aspect).floorToDouble();
  final ch = aspect >= 1 ? (640 / aspect).floorToDouble() : 640.0;
  final px = ((640 - cw) / 2).floorToDouble(),
      py = ((640 - ch) / 2).floorToDouble();
  return PoseFrame(
    seconds,
    List.generate(17, (joint) {
      var ix = 0, iy = 0;
      for (var i = 1; i < 384; i++) {
        if (sx[joint * 384 + i] > sx[joint * 384 + ix]) ix = i;
      }
      for (var i = 1; i < 512; i++) {
        if (sy[joint * 512 + i] > sy[joint * 512 + iy]) iy = i;
      }
      final score = math.min(sx[joint * 384 + ix], sy[joint * 512 + iy]);
      final x =
          ((box.left + box.right) / 2 + (ix / 384 - .5) * scaleX - px) / cw;
      final y =
          ((box.top + box.bottom) / 2 + (iy / 512 - .5) * scaleY - py) / ch;
      if (!score.isFinite || score < .3 || x < 0 || x > 1 || y < 0 || y > 1) {
        return const PosePoint(0, 0, 0);
      }
      return PosePoint(x, y, score.clamp(0.0, 1.0));
    }),
  );
}
