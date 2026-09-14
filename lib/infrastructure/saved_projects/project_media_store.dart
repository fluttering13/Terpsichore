import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/shared_video_playback/video_source.dart';

final class ProjectMediaStore {
  const ProjectMediaStore();

  Future<VideoSource> persistVideo(VideoSource source) async {
    final input = File(source.path);
    if (!await input.exists()) throw StateError('找不到影片：${source.label}');
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/saved_projects/media');
    await directory.create(recursive: true);
    final managedPrefix = '${directory.absolute.path}${Platform.pathSeparator}';
    if (input.absolute.path.startsWith(managedPrefix)) return source;

    final originalName = input.uri.pathSegments.last;
    final dot = originalName.lastIndexOf('.');
    final extension = dot < 0
        ? ''
        : originalName.substring(dot).replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '');
    final safeId = source.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final output = File('${directory.path}/$safeId$extension');
    if (!await output.exists() ||
        await output.length() != await input.length()) {
      await input.copy(output.path);
    }
    return VideoSource(id: source.id, path: output.path, label: source.label);
  }
}
