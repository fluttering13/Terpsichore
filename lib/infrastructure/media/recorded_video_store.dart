import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

final class RecordedVideoStore {
  const RecordedVideoStore();

  Future<String> persist(XFile temporaryFile) async {
    final documents = await getApplicationDocumentsDirectory();
    final recordings = Directory(
      '${documents.path}${Platform.pathSeparator}recordings',
    );
    if (!await recordings.exists()) await recordings.create(recursive: true);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final destination =
        '${recordings.path}${Platform.pathSeparator}dance-$timestamp.mp4';
    await File(temporaryFile.path).copy(destination);
    return destination;
  }
}
