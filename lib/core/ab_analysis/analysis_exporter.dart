import 'analysis_project.dart';

final class AnalysisExportRequest {
  const AnalysisExportRequest(this.project);

  final AnalysisProject project;
}

sealed class AnalysisExportResult {
  const AnalysisExportResult();
}

final class AnalysisExported extends AnalysisExportResult {
  const AnalysisExported(this.path);
  final String path;
}

final class AnalysisExportUnsupported extends AnalysisExportResult {
  const AnalysisExportUnsupported(this.reason);
  final String reason;
}

final class AnalysisExportFailed extends AnalysisExportResult {
  const AnalysisExportFailed(this.reason);
  final String reason;
}

abstract interface class AnalysisExporter {
  Future<AnalysisExportResult> export(AnalysisExportRequest request);
}
