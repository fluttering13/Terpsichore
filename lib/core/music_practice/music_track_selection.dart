import 'stem_separation.dart';

final class MusicTrackSelection {
  MusicTrackSelection.original() : original = true, stems = const {};

  MusicTrackSelection.stems(Set<MusicStem> stems)
    : original = false,
      stems = Set.unmodifiable(stems);

  final bool original;
  final Set<MusicStem> stems;

  bool get canPractice => original || stems.isNotEmpty;

  MusicTrackSelection selectOriginal() => MusicTrackSelection.original();

  MusicTrackSelection toggleStem(MusicStem stem) {
    final next = Set<MusicStem>.of(stems);
    next.contains(stem) ? next.remove(stem) : next.add(stem);
    return MusicTrackSelection.stems(next);
  }
}
