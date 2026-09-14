import 'package:file_picker/file_picker.dart';

import '../../core/music_practice/music_practice_source.dart';

final class LocalMusicMediaPicker {
  const LocalMusicMediaPicker();

  static const _audioExtensions = {'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'};
  static const _extensions = [
    'mp3',
    'wav',
    'm4a',
    'aac',
    'flac',
    'ogg',
    'mp4',
    'mov',
    'mkv',
    'webm',
  ];

  Future<MusicPracticeSource?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _extensions,
    );
    final path = file?.path;
    if (file == null || path == null) return null;
    final extension = file.extension?.toLowerCase() ?? '';
    return MusicPracticeSource(
      path: path,
      name: file.name,
      kind: _audioExtensions.contains(extension)
          ? MusicPracticeInputKind.audio
          : MusicPracticeInputKind.video,
    );
  }
}
