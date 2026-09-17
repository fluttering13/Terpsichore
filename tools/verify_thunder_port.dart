// Local cached-evidence parity check; does not run model inference.
import 'dart:convert';
import 'dart:io';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';
import 'package:terpsichore/core/ab_analysis/pose_post_processing.dart';

void main() {
  for (final entry in [
    ('airflare', 'rot4', 1.3, .35, 0.0, 4.2, 9 / 16, 9 / 16, .26, .715),
    ('choreo', 'raw', 5.7, 1.0, 1.2, 7.2, 484 / 640, 398 / 620, 1.51, .99),
  ]) {
    final data =
        jsonDecode(
              File(
                'build/pose-expanded/${entry.$1}-movenet-thunder-${entry.$2}-selected.json',
              ).readAsStringSync(),
            )
            as Map;
    PoseSequence sequence(String side, double aspect) {
      // Cached points are pixel coordinates; dimensions are stored separately
      // in the input videos. Aspect normalization is invariant to uniform scale.
      final height = entry.$1 == 'airflare'
          ? (side == 'a' ? 1280.0 : 1920.0)
          : (side == 'a' ? 640.0 : 620.0);
      return medianPoseSequence(
        PoseSequence(
          (data[side] as List).map((dynamic row) {
            final points = row['person']?['points'] as List?;
            return PoseFrame(
              (row['t'] as num).toDouble(),
              points == null
                  ? List.filled(17, const PosePoint(0, 0, 0))
                  : points
                        .map(
                          (p) => PosePoint(
                            (p[0] as num) / (height * aspect),
                            (p[1] as num) / height,
                            (p[2] as num).toDouble(),
                          ),
                        )
                        .toList(),
            );
          }).toList(),
          aspect,
        ),
        .5,
      );
    }

    final result = solveThunderAlignment(
      PoseAlignmentRequest(
        a: sequence('a', entry.$7),
        b: sequence('b', entry.$8),
        aStart: 0,
        aEnd: entry.$3,
        aRate: entry.$4,
        bStart: 0,
        bEnd: entry.$6,
        bAnchorStart: entry.$5,
        bAnchorEnd: entry.$6,
      ),
    );
    stdout.writeln(
      '${entry.$1}: start=${result?.bStart}, rate=${result?.bRate}, loss=${result?.error}',
    );
    if (result == null ||
        (result.bStart - entry.$9).abs() > .011 ||
        (result.bRate - entry.$10).abs() > .006) {
      throw StateError('Dart/desktop cached-evidence result mismatch');
    }
  }
}
