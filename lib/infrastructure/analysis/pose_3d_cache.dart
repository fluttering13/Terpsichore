import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/ab_analysis/analysis_project.dart';
import '../../core/ab_analysis/pose_3d.dart';

/// Retain the latest successful comparison across navigation and app restarts.
abstract final class Pose3dCache {
  static Map<String, Object> identity(AnalysisProject p) => {
    'tracks': [
      for (final t in [p.trackA, p.trackB])
        {
          'path': t.source.path,
          'duration': t.mediaDuration.inMicroseconds,
          'start': t.trim.start.inMicroseconds,
          'end': t.trim.end.inMicroseconds,
          'rate': t.rate.value,
        },
    ],
  };
  static Future<File> _file([String? savedProjectId]) async {
    if (savedProjectId == null) {
      return File(
        '${(await getApplicationSupportDirectory()).path}/pose3d-last.json',
      );
    }
    final name = base64Url.encode(utf8.encode(savedProjectId));
    return File(
      '${(await getApplicationDocumentsDirectory()).path}/saved_projects/pose3d/$name.json',
    );
  }

  static Future<void> _writes = Future.value();
  static Future<void> save(Pose3dComparison result, {String? savedProjectId}) {
    final write = _writes.then((_) => _save(result, savedProjectId));
    _writes = write.catchError((Object _) {});
    return write;
  }

  static Future<void> _save(
    Pose3dComparison result,
    String? savedProjectId,
  ) async {
    List<Object> frames(Pose3dSequence seq) => [
      for (final f in seq.frames)
        [
          f.seconds,
          f.points == null
              ? null
              : [
                  for (final p in f.points!) [p.x, p.y, p.z, p.confidence],
                ],
        ],
    ];
    final data = {
      'version': 1,
      'project': identity(result.project),
      'settings': result.settings.toJson(),
      'a': frames(result.a),
      'b': frames(result.b),
    };
    final file = await _file(savedProjectId);
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode(data), flush: true);
    await pending.rename(file.path);
  }

  static Future<Pose3dComparison?> load(
    AnalysisProject project, {
    String? savedProjectId,
  }) async {
    try {
      final file = await _file(savedProjectId);
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString()) as Map;
      if (data['version'] != 1 ||
          jsonEncode(data['project']) != jsonEncode(identity(project))) {
        return null;
      }
      if ((data['settings'] as Map)['model'] != 'nlfInt8') return null;
      final settings = Pose3dSettings.fromJson(data['settings']);
      Pose3dSequence seq(Object? value) {
        final rows = value as List;
        final result = <Pose3dFrame>[];
        for (final raw in rows) {
          final row = raw as List;
          final time = (row[0] as num).toDouble();
          if (!time.isFinite ||
              time < 0 ||
              result.isNotEmpty && time <= result.last.seconds) {
            throw const FormatException('Invalid time');
          }
          final points = row[1] == null
              ? null
              : [
                  for (final point in row[1] as List)
                    Pose3dPoint(
                      (point[0] as num).toDouble(),
                      (point[1] as num).toDouble(),
                      (point[2] as num).toDouble(),
                      (point[3] as num).toDouble(),
                    ),
                ];
          if (points != null &&
              (points.length != 17 ||
                  points.any(
                    (p) =>
                        ![p.x, p.y, p.z, p.confidence].every((v) => v.isFinite),
                  ))) {
            throw const FormatException('Invalid pose');
          }
          result.add(Pose3dFrame(time, points));
        }
        if (result.isEmpty) throw const FormatException('Empty result');
        return Pose3dSequence(result, settings.fps);
      }

      return Pose3dComparison(
        project,
        settings,
        seq(data['a']),
        seq(data['b']),
      );
    } catch (_) {
      return null;
    }
  }
}
