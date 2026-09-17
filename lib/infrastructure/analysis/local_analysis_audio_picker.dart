import 'package:file_picker/file_picker.dart';

import '../../core/ab_analysis/analysis_project.dart';

final class LocalAnalysisAudioPicker {
  const LocalAnalysisAudioPicker();

  static const _extensions = ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'];

  Future<AnalysisCustomAudio?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _extensions,
    );
    final path = file?.path;
    if (file == null || path == null || path.isEmpty) return null;
    return AnalysisCustomAudio(
      id: '${file.name}-${DateTime.now().microsecondsSinceEpoch}',
      path: path,
      label: file.name,
    );
  }
}
