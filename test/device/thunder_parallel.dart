// Foreground benchmark only. Does not change normal UI scheduling.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';
import 'package:terpsichore/core/ab_analysis/pose_post_processing.dart';
import 'package:terpsichore/infrastructure/analysis/movenet_analyzer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('Parallel benchmark');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder(
            valueListenable: status,
            builder: (_, text, _) => Text(text),
          ),
        ),
      ),
    ),
  );
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/thunder-parallel-result.json');
  final rows = <Map<String, Object?>>[];
  final report = <String, Object?>{'status': 'running', 'runs': rows};
  Future<void> save() => file.writeAsString(jsonEncode(report), flush: true);
  await save();
  try {
    const onlyBackend = String.fromEnvironment('POSE_ONLY_BACKEND');
    final backend = onlyBackend.isNotEmpty ? onlyBackend : 'mlkit-accurate';
    final configs = [(false, 1, backend), (true, 1, backend)];
    for (var repeat = 0; repeat < 2; repeat++) {
      for (final config in repeat == 0 ? configs : configs.reversed) {
        if (onlyBackend.isNotEmpty && config.$3 != onlyBackend) continue;
        for (final c in [
          ('airflare', 1.3, .35, 0.0, 4.2, 4.245, 9 / 16, 9 / 16),
          ('choreo', 5.7, 1.0, 1.2, 7.2, 7.249, 484 / 640, 398 / 620),
        ]) {
          final name = '${config.$3}${config.$1 ? '' : '-sequential'}';
          status.value = 'Round ${repeat + 1} $name ${c.$1}';
          final radius = (c.$5 - c.$4) * .1;
          final startB = (c.$4 - radius).clamp(0.0, c.$6);
          final endB = (c.$5 + radius).clamp(0.0, c.$6);
          final tracks = [('a', 0.0, c.$2, c.$7), ('b', startB, endB, c.$8)];
          final analyzers = List.generate(
            2,
            (_) => MoveNetAnalyzer(
              intraOpThreads: config.$2,
              nativeParallelBackend: config.$3.startsWith('mlkit'),
              nativeBackend: config.$3,
              multiPersonFiltering: !config.$3.startsWith('mlkit'),
            ),
          );
          final metrics = List<Map<String, Object?>?>.filled(2, null);
          Future<PoseSequence> run(int index) async {
            final t = tracks[index];
            final timer = Stopwatch()..start();
            try {
              final sequence = await analyzers[index].analyze(
                path: '${dir.path}/thunder-${c.$1}-${t.$1}.mp4',
                start: t.$2,
                end: t.$3,
                aspectRatio: t.$4,
                samplingFps: 12,
                onProgress: (_) {},
              );
              if (analyzers[index].metrics['thunder_calls'] !=
                  sequence.frames.length) {
                throw StateError(
                  'Expected exactly one inference per sampled frame',
                );
              }
              metrics[index] = {
                'side': t.$1,
                'milliseconds': timer.elapsedMilliseconds,
                'metrics': Map.of(analyzers[index].metrics),
                'native_intervals': analyzers[index].nativeIntervals,
                'frames': sequence.frames
                    .map(
                      (f) => {
                        't': f.seconds,
                        'points': f.points
                            .map((p) => [p.x, p.y, p.score])
                            .toList(),
                      },
                    )
                    .toList(),
              };
              return sequence;
            } catch (_) {
              for (final a in analyzers) {
                a.cancelled = true;
              }
              rethrow;
            }
          }

          final wall = Stopwatch()..start();
          final sequences = config.$1
              ? await Future.wait([run(0), run(1)])
              : [await run(0), await run(1)];
          final analysisUs = wall.elapsedMicroseconds;
          final post = Stopwatch()..start();
          final a = medianPoseSequence(sequences[0], .5);
          final b = medianPoseSequence(sequences[1], .5);
          final medianUs = post.elapsedMicroseconds;
          post.reset();
          final result = solveThunderAlignment(
            PoseAlignmentRequest(
              a: a,
              b: b,
              aStart: 0,
              aEnd: c.$2,
              aRate: c.$3,
              bStart: startB,
              bEnd: endB,
              bAnchorStart: c.$4,
              bAnchorEnd: c.$5,
            ),
          );
          rows.add({
            'repeat': repeat,
            'configuration': name,
            'case': c.$1,
            'analysis_us': analysisUs,
            'median_us': medianUs,
            'search_us': post.elapsedMicroseconds,
            'total_us': wall.elapsedMicroseconds,
            'tracks': metrics,
            'result': result == null
                ? null
                : {
                    'b_start': result.bStart,
                    'b_rate': result.bRate,
                    'error': result.error,
                    'coverage': result.coverage,
                    'ambiguous': result.ambiguous,
                  },
          });
          await save();
        }
      }
    }
    final temp = await getTemporaryDirectory();
    final leftover = await temp
        .list()
        .where((f) => f.path.split('/').last.startsWith('thunder-only-'))
        .length;
    report['leftover_workspaces'] = leftover;
    if (leftover != 0) throw StateError('Leaked workspaces: $leftover');
    report['status'] = 'complete';
  } catch (e, s) {
    report.addAll({'status': 'failed', 'error': '$e', 'stack': '$s'});
  }
  await save();
  status.value = 'Parallel benchmark ${report['status']}';
}
