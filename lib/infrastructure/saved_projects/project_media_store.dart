import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/ab_analysis/analysis_project.dart';
import '../../core/shared_video_playback/video_source.dart';

final class ProjectMediaStore {
  const ProjectMediaStore();

  Future<VideoSource> persistVideo(VideoSource source) async {
    final path = await _persist(
      id: source.id,
      path: source.path,
      label: source.label,
      kind: '影片',
    );
    return VideoSource(id: source.id, path: path, label: source.label);
  }

  Future<AnalysisCustomAudio> persistAudio(AnalysisCustomAudio source) async {
    final path = await _persist(
      id: source.id,
      path: source.path,
      label: source.label,
      kind: '音訊',
    );
    return AnalysisCustomAudio(
      id: source.id,
      path: path,
      label: source.label,
      mediaDuration: source.mediaDuration,
      trim: source.trim,
      timelineStart: source.timelineStart,
    );
  }

  Future<String> _persist({
    required String id,
    required String path,
    required String label,
    required String kind,
  }) async {
    final input = File(path);
    if (!await input.exists()) throw StateError('找不到$kind：$label');
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/saved_projects/media');
    await directory.create(recursive: true);
    final managedPrefix = '${directory.absolute.path}${Platform.pathSeparator}';
    if (input.absolute.path.startsWith(managedPrefix)) return input.path;

    final originalName = input.uri.pathSegments.last;
    final dot = originalName.lastIndexOf('.');
    final extension = dot < 0
        ? ''
        : originalName.substring(dot).replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '');
    final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final output = File('${directory.path}/$safeId$extension');
    if (!await output.exists() ||
        await output.length() != await input.length()) {
      await input.copy(output.path);
    }
    return output.path;
  }
}
