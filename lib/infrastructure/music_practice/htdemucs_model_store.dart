import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/music_practice/stem_separation.dart';

final class HtdemucsModelStore {
  const HtdemucsModelStore();

  static const modelUrl =
      'https://huggingface.co/StemSplitio/htdemucs-6s-onnx/resolve/main/htdemucs_6s_fp16weights.onnx';
  static const _minimumValidBytes = 100 * 1024 * 1024;
  static const _estimatedBytes = 136 * 1024 * 1024;

  Future<String> obtain({
    required void Function(StemSeparationUpdate update) onProgress,
  }) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/models');
    await directory.create(recursive: true);
    final model = File('${directory.path}/htdemucs_6s_fp16weights.onnx');
    if (await model.exists() && await model.length() >= _minimumValidBytes) {
      onProgress(
        const StemSeparationUpdate(
          stage: StemSeparationStage.downloadingModel,
          progress: 1,
        ),
      );
      return model.path;
    }

    final temporary = File('${model.path}.download');
    if (await temporary.exists()) await temporary.delete();
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(modelUrl));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('模型下載失敗（HTTP ${response.statusCode}）');
      }
      final expected = response.contentLength > 0
          ? response.contentLength
          : _estimatedBytes;
      final sink = temporary.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(
            StemSeparationUpdate(
              stage: StemSeparationStage.downloadingModel,
              progress: (received / expected).clamp(0, 1),
            ),
          );
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (await temporary.length() < _minimumValidBytes) {
        throw const FormatException('下載的 AI 分離模型不完整');
      }
      if (await model.exists()) await model.delete();
      await temporary.rename(model.path);
      return model.path;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}
