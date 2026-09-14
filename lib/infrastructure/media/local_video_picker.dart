import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../core/shared_video_playback/video_source.dart';

final class LocalVideoPicker {
  const LocalVideoPicker();

  Future<VideoSource?> pick() async {
    final file = await FilePicker.pickFile(type: FileType.video);
    if (file == null) return null;
    // Browser-picked files are exposed through a blob URI and intentionally
    // have no local path. Native platforms continue to use the local path.
    final location = kIsWeb ? file.uri.toString() : file.path;
    if (location == null || location.isEmpty) return null;
    return VideoSource(
      id: '${file.name}-${DateTime.now().microsecondsSinceEpoch}',
      path: location,
      label: file.name,
    );
  }
}
