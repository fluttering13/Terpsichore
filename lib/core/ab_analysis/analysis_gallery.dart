final class AnalysisGalleryFolder {
  const AnalysisGalleryFolder._(this.path);

  static const defaultFolder = AnalysisGalleryFolder._('Terpsichore');

  final String path;

  static AnalysisGalleryFolder? tryParse(String input) {
    final normalized = input
        .trim()
        .replaceAll('\\', '/')
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .join('/');
    if (normalized.isEmpty ||
        normalized
            .split('/')
            .any(
              (segment) =>
                  segment == '.' ||
                  segment == '..' ||
                  RegExp(r'[:*?"<>|]').hasMatch(segment),
            )) {
      return null;
    }
    return AnalysisGalleryFolder._(normalized);
  }
}

sealed class AnalysisGalleryResult {
  const AnalysisGalleryResult();
}

final class AnalysisSavedToGallery extends AnalysisGalleryResult {
  const AnalysisSavedToGallery(this.location);

  final String? location;
}

final class AnalysisGallerySaveFailed extends AnalysisGalleryResult {
  const AnalysisGallerySaveFailed(this.reason);

  final String reason;
}

abstract interface class AnalysisGallery {
  Future<AnalysisGalleryResult> save(
    String exportedVideoPath, {
    required AnalysisGalleryFolder folder,
  });
}
