enum MusicPracticeInputKind { audio, video }

final class MusicPracticeSource {
  const MusicPracticeSource({
    required this.path,
    required this.name,
    required this.kind,
  });

  final String path;
  final String name;
  final MusicPracticeInputKind kind;
}
