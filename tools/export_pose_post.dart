// Run with dart: uses exactly the same post-processing code as the app.
import 'dart:convert';
import 'dart:io';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';
import 'package:terpsichore/core/ab_analysis/pose_post_processing.dart';

void main(List<String> args) {
  final input = jsonDecode(File(args[0]).readAsStringSync()) as Map;
  final output = <String, Object>{};
  for (final clip in ['a', 'b']) {
    final sequence = PoseSequence(
      (input[clip]['frames'] as List)
          .map(
            (f) => PoseFrame(
              (f['t'] as num).toDouble(),
              (f['points'] as List)
                  .map(
                    (p) => PosePoint(
                      (p[0] as num).toDouble(),
                      (p[1] as num).toDouble(),
                      (p[2] as num).toDouble(),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
      9 / 16,
    );
    final variants = <String, Object>{};
    for (final window in [0.0, .15, .3, .5]) {
      final watch = Stopwatch()..start();
      final processed = smoothPoseSequence(sequence, window);
      final elapsed = watch.elapsedMicroseconds;
      var filled = 0;
      final frames = <Object>[];
      // Resample only for viewing: 30fps does not mean 30fps inference.
      final duration = clip == 'a' ? 1.333333 : 3.633333;
      for (var i = 0; i / 30 < duration; i++) {
        final f = processed.at(i / 30);
        frames.add({
          't': i / 30,
          'points': f?.points
              .map((p) => [p.x, p.y, p.score, p.inferred])
              .toList(),
        });
      }
      for (final f in processed.frames) {
        filled += f.points.where((p) => p.inferred).length;
      }
      variants['$window'] = {
        'frames': frames,
        'filledJointSamples': filled,
        'postMicroseconds': elapsed,
      };
      stdout.writeln(
        '$clip window=$window seconds, filled=$filled joint samples, post=$elapsed us',
      );
    }
    output[clip] = variants;
  }
  File(args[1]).writeAsStringSync(jsonEncode(output));
}
