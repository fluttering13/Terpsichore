import 'music_practice_source.dart';

enum MusicStem { drums, bass, other, vocals, guitar, piano }

enum StemSeparationStage { preparingAudio, downloadingModel, separating }

final class StemSeparationUpdate {
  const StemSeparationUpdate({required this.stage, required this.progress});

  final StemSeparationStage stage;
  final double progress;
}

final class PreparedMusic {
  const PreparedMusic({
    required this.source,
    required this.originalWavPath,
    required this.workspacePath,
    required this.duration,
  });

  final MusicPracticeSource source;
  final String originalWavPath;
  final String workspacePath;
  final Duration duration;
}

final class SeparatedStems {
  const SeparatedStems({required this.prepared, required this.paths});

  final PreparedMusic prepared;
  final Map<MusicStem, String> paths;
}

abstract interface class MusicMediaPreparer {
  Future<PreparedMusic> prepare(
    MusicPracticeSource source, {
    required void Function(StemSeparationUpdate update) onProgress,
  });
}

abstract interface class MusicStemSeparator {
  Future<SeparatedStems> separate(
    PreparedMusic music, {
    required void Function(StemSeparationUpdate update) onProgress,
  });
}

abstract interface class MusicPracticeMixBuilder {
  Future<String> build({
    required SeparatedStems stems,
    required Set<MusicStem> selection,
  });
}
