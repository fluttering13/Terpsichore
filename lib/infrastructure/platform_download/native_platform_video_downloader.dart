import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/platform_download/platform_video.dart';

final class NativePlatformVideoDownloader implements PlatformVideoDownloader {
  const NativePlatformVideoDownloader();
  static const _channel = MethodChannel('terpsichore/platform_download');
  static const _events = EventChannel('terpsichore/platform_download/progress');

  @override
  Stream<DownloadProgress> get progress {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const Stream.empty();
    }
    return _events.receiveBroadcastStream().map((event) {
      final data = event as Map;
      return DownloadProgress(
        data['jobId'] as String,
        data['phase'] as String,
        (data['progress'] as num?)?.toDouble(),
        item: (data['item'] as num?)?.toInt() ?? 0,
        total: (data['total'] as num?)?.toInt() ?? 0,
      );
    });
  }

  Future<Map<Object?, Object?>> _invoke(
    String method,
    Map<String, Object> arguments,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const DownloadException('UNSUPPORTED_PLATFORM');
    }
    try {
      return await _channel.invokeMethod<Map<Object?, Object?>>(
            method,
            arguments,
          ) ??
          {};
    } on PlatformException catch (error) {
      throw DownloadException(error.code);
    } on MissingPluginException {
      throw const DownloadException('UNSUPPORTED_PLATFORM');
    }
  }

  @override
  Future<PlatformVideo> inspect(String url, String jobId) async =>
      PlatformVideo.fromMap(
        await _invoke('inspect', {'url': url, 'jobId': jobId}),
      );

  @override
  Future<DownloadReceipt> download(
    PlatformVideo video,
    PlatformVideoFormat format,
    String jobId,
  ) async {
    final data = await _invoke('download', {
      'snapshotId': video.snapshotId,
      'formatId': format.id,
      'jobId': jobId,
    });
    return DownloadReceipt(data['uri'] as String, data['location'] as String);
  }

  @override
  Future<DownloadReceipt> downloadSelection(
    List<PlatformVideo> videos,
    List<PlatformVideoFormat> formats,
    String jobId, {
    required bool combine,
  }) async {
    final data = await _invoke('downloadSelection', {
      'jobId': jobId,
      'combine': combine,
      'items': [
        for (var i = 0; i < videos.length; i++)
          {'snapshotId': videos[i].snapshotId, 'formatId': formats[i].id},
      ],
    });
    return DownloadReceipt(
      data['uri'] as String? ?? '',
      data['location'] as String? ?? '',
      issues: (data['issues'] as List? ?? []).cast<String>(),
    );
  }

  @override
  Future<void> cancel(String jobId) async {
    await _invoke('cancel', {'jobId': jobId});
  }
}
