import 'dart:io';

import 'package:saver_gallery/saver_gallery.dart';

import '../../core/ab_analysis/analysis_gallery.dart';

final class DeviceAnalysisGallery implements AnalysisGallery {
  const DeviceAnalysisGallery();

  @override
  Future<AnalysisGalleryResult> save(
    String exportedVideoPath, {
    required AnalysisGalleryFolder folder,
  }) async {
    final fileName = File(exportedVideoPath).uri.pathSegments.last;
    try {
      final result = await SaverGallery.saveFile(
        filePath: exportedVideoPath,
        fileName: fileName,
        albumPath: folder.path,
        skipIfExists: false,
      );
      if (result.isSuccess) {
        return AnalysisSavedToGallery(result.savedUri);
      }
      return AnalysisGallerySaveFailed(result.errorMessage ?? '裝置媒體庫沒有回傳失敗原因');
    } catch (error) {
      return AnalysisGallerySaveFailed(error.toString());
    }
  }
}
