import 'dart:math' as math;
import 'dart:typed_data';
import 'pose_alignment.dart';
import 'rtmpose_processing.dart';

bool isThunderPoseReliable(PoseFrame frame) {
  final body = frame.points.skip(5);
  return [5, 6, 11, 12].every((j) => frame.points[j].score >= .3) &&
      body.where((p) => p.score >= .3).length >= 10 &&
      body.fold(0.0, (s, p) => s + p.score) / 12 >= .45;
}

/// Counter-clockwise square rotation, matching numpy.rot90 used by experiments.
Uint8List rotatePoseImage((Uint8List, int) request) {
  final (bytes, turns) = request;
  if (turns == 0) return bytes;
  final out = Uint8List(bytes.length);
  for (var y = 0; y < 640; y++) {
    for (var x = 0; x < 640; x++) {
      final (sx, sy) = restorePosePixel(x.toDouble(), y.toDouble(), turns);
      final source = (sy.toInt() * 640 + sx.toInt()) * 3;
      final dest = (y * 640 + x) * 3;
      out.setRange(dest, dest + 3, bytes, source);
    }
  }
  return out;
}

(double, double) restorePosePixel(double x, double y, int turns) =>
    switch (turns) {
      0 => (x, y),
      1 => (639 - y, x),
      2 => (639 - x, 639 - y),
      3 => (y, 639 - x),
      _ => throw ArgumentError('Invalid rotation'),
    };

PersonBox restorePoseBox(PersonBox box, int turns) {
  final corners = [
    restorePosePixel(box.left, box.top, turns),
    restorePosePixel(box.right, box.bottom, turns),
  ];
  return PersonBox(
    math.min(corners[0].$1, corners[1].$1),
    math.min(corners[0].$2, corners[1].$2),
    math.max(corners[0].$1, corners[1].$1),
    math.max(corners[0].$2, corners[1].$2),
    box.score,
  );
}

PoseFrame restoreMoveNet(PoseFrame squareFrame, double aspect, int turns) {
  final cw = aspect >= 1 ? 640.0 : (640 * aspect).floorToDouble();
  final ch = aspect >= 1 ? (640 / aspect).floorToDouble() : 640.0;
  final px = ((640 - cw) / 2).floorToDouble();
  final py = ((640 - ch) / 2).floorToDouble();
  return PoseFrame(
    squareFrame.seconds,
    squareFrame.points.map((p) {
      final (sx, sy) = restorePosePixel(p.x * 640, p.y * 640, turns);
      final x = (sx - px) / cw, y = (sy - py) / ch;
      if (p.score <= 0 || x < 0 || x > 1 || y < 0 || y > 1) {
        return const PosePoint(0, 0, 0);
      }
      return PosePoint(x, y, p.score);
    }).toList(),
  );
}

/// Thunder FP32 export expects RGB int32 NHWC, 0..255 (not float NCHW).
Int32List prepareMoveNet(PoseCropRequest request) =>
    prepareRotatedMoveNet((request, 0));

/// Sample the rotated ROI directly: no full 640-square rotated copy is needed.
/// Box and padding are in rotated coordinates, as in the legacy crop path.
Int32List prepareRotatedMoveNet((PoseCropRequest, int) input) {
  final (request, rotation) = input;
  if (request.bgr.length != 640 * 640 * 3 ||
      !request.aspectRatio.isFinite ||
      request.aspectRatio <= 0) {
    throw ArgumentError('MoveNet 影格尺寸不相容');
  }
  final box = request.box;
  final side = math.max(box.width, box.height) * 1.25;
  final cx = (box.left + box.right) / 2;
  final cy = (box.top + box.bottom) / 2;
  final aspect = request.aspectRatio;
  final cw = aspect >= 1 ? 640.0 : (640 * aspect).floorToDouble();
  final ch = aspect >= 1 ? (640 / aspect).floorToDouble() : 640.0;
  final px = ((640 - cw) / 2).floorToDouble();
  final py = ((640 - ch) / 2).floorToDouble();
  int index(int x, int y) {
    if (x < px || x >= px + cw || y < py || y >= py + ch) return -1;
    return switch (rotation) {
      0 => (y * 640 + x) * 3,
      1 => (x * 640 + 639 - y) * 3,
      2 => ((639 - y) * 640 + 639 - x) * 3,
      3 => ((639 - x) * 640 + y) * 3,
      _ => throw ArgumentError('Invalid rotation'),
    };
  }

  final result = Int32List(256 * 256 * 3);
  for (var y = 0; y < 256; y++) {
    final sy = cy + (y / 256 - .5) * side;
    final iy = sy.floor(), fy = sy - sy.floor();
    for (var x = 0; x < 256; x++) {
      final sx = cx + (x / 256 - .5) * side;
      final ix = sx.floor(), fx = sx - sx.floor();
      final a = index(ix, iy), b = index(ix + 1, iy);
      final d = index(ix, iy + 1), e = index(ix + 1, iy + 1);
      for (var c = 0; c < 3; c++) {
        final bgrChannel = 2 - c;
        result[(y * 256 + x) * 3 + c] =
            ((a < 0 ? 0 : request.bgr[a + bgrChannel]) * (1 - fx) * (1 - fy) +
                    (b < 0 ? 0 : request.bgr[b + bgrChannel]) * fx * (1 - fy) +
                    (d < 0 ? 0 : request.bgr[d + bgrChannel]) * (1 - fx) * fy +
                    (e < 0 ? 0 : request.bgr[e + bgrChannel]) * fx * fy)
                .round()
                .clamp(0, 255);
      }
    }
  }
  return result;
}

Float32List prepareRotatedDetector((Uint8List, int) input) =>
    preparePersonDetector(rotatePoseImage(input));

PoseFrame decodeMoveNet(
  List<double> values,
  PersonBox box,
  double seconds,
  double aspect,
) {
  if (values.length != 17 * 3) throw StateError('MoveNet Thunder 關節輸出不相容');
  final side = math.max(box.width, box.height) * 1.25;
  final cx = (box.left + box.right) / 2, cy = (box.top + box.bottom) / 2;
  final cw = aspect >= 1 ? 640.0 : (640 * aspect).floorToDouble();
  final ch = aspect >= 1 ? (640 / aspect).floorToDouble() : 640.0;
  final px = ((640 - cw) / 2).floorToDouble(),
      py = ((640 - ch) / 2).floorToDouble();
  return PoseFrame(
    seconds,
    List.generate(17, (j) {
      final y = (cy + (values[j * 3] - .5) * side - py) / ch;
      final x = (cx + (values[j * 3 + 1] - .5) * side - px) / cw;
      final score = values[j * 3 + 2];
      if (![x, y, score].every((v) => v.isFinite) ||
          x < 0 ||
          x > 1 ||
          y < 0 ||
          y > 1 ||
          score < 0) {
        return const PosePoint(0, 0, 0);
      }
      // Preserve raw confidence; display/alignment policies own their thresholds.
      return PosePoint(x, y, score.clamp(0.0, 1.0));
    }),
  );
}
