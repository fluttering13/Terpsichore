enum RecordingOutput { dancerOnly, referenceAndDancer }

extension RecordingOutputLabel on RecordingOutput {
  String get label => switch (this) {
    RecordingOutput.dancerOnly => '只有 B（我的錄影）',
    RecordingOutput.referenceAndDancer => 'A + B（參考與我的錄影）',
  };
}
