// Native fixed-FPS extraction/timeline check on the authorized Airflare A.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terpsichore/infrastructure/analysis/movenet_analyzer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Thunder FPS validation'))),
    ),
  );
  final directory = await getApplicationSupportDirectory();
  final report = <String, Object?>{'status': 'running', 'results': <Object?>[]};
  try {
    for (final fps in [6, 12, 30]) {
      final analyzer = MoveNetAnalyzer.forApp(
        isAndroid: Platform.isAndroid,
        trackMainPerson: true,
      );
      final sequence = await analyzer.analyze(
        path: '${directory.path}/thunder-airflare-a.mp4',
        start: 0,
        end: 1,
        aspectRatio: 9 / 16,
        samplingFps: fps,
        onProgress: (_) {},
      );
      if (sequence.frames.length != fps) {
        throw StateError(
          'Wrong frame count for $fps: ${sequence.frames.length}',
        );
      }
      for (var i = 0; i < sequence.frames.length; i++) {
        if ((sequence.frames[i].seconds - i / fps).abs() > 1e-6) {
          throw StateError('Timestamp mismatch at $fps/$i');
        }
      }
      (report['results'] as List).add({
        'fps': fps,
        'frames': sequence.frames.length,
        'metrics': analyzer.metrics,
      });
    }
    report['status'] = 'complete';
  } catch (error) {
    report.addAll({'status': 'failed', 'error': '$error'});
  }
  await File(
    '${directory.path}/thunder-fps-result.json',
  ).writeAsString(jsonEncode(report));
  debugPrint('THUNDER_FPS ${report['status']}');
}
