import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/analysis_gallery.dart';

void main() {
  test('normalizes a nested analysis gallery folder', () {
    expect(
      AnalysisGalleryFolder.tryParse(' Terpsichore \\ A+B ')?.path,
      'Terpsichore/A+B',
    );
  });

  test('rejects empty and unsafe analysis gallery folders', () {
    expect(AnalysisGalleryFolder.tryParse('  '), isNull);
    expect(AnalysisGalleryFolder.tryParse('../secret'), isNull);
    expect(AnalysisGalleryFolder.tryParse('bad:name'), isNull);
  });
}
