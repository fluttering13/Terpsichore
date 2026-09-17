enum VideoOutputFormat {
  mp4('MP4', 'mp4'),
  mov('MOV', 'mov'),
  mkv('Matroska (MKV)', 'mkv'),
  avi('AVI', 'avi');

  const VideoOutputFormat(this.label, this.extension);

  final String label;
  final String extension;

  String get mimeType => switch (this) {
    VideoOutputFormat.mp4 => 'video/mp4',
    VideoOutputFormat.mov => 'video/quicktime',
    VideoOutputFormat.mkv => 'video/x-matroska',
    VideoOutputFormat.avi => 'video/x-msvideo',
  };

  List<VideoCodec> get supportedCodecs => this == VideoOutputFormat.avi
      ? const [VideoCodec.mpeg4]
      : VideoCodec.values;

  List<String> encodingArguments({
    required VideoQuality quality,
    required VideoCodec codec,
    required VideoResolution resolution,
  }) => [
    if (resolution.scaleFilter case final filter?) ...['-vf', filter],
    ...codec.arguments(quality, outputFormat: this),
    if (this == VideoOutputFormat.avi) ...[
      '-c:a',
      'pcm_s16le',
    ] else ...[
      '-c:a',
      'aac',
      '-b:a',
      '192k',
    ],
  ];
}

enum VideoCodec {
  h264('H.264 / AVC', '相容性最好，建議用於 720p、1080p'),
  hevc('H.265 / HEVC', '壓縮效率較佳，建議用於 4K'),
  mpeg4('MPEG-4 Part 2', '舊式編碼，僅建議用於 AVI 或較低解析度');

  const VideoCodec(this.label, this.description);

  final String label;
  final String description;

  List<String> arguments(
    VideoQuality quality, {
    required VideoOutputFormat outputFormat,
  }) => switch (this) {
    VideoCodec.h264 => [
      '-c:v',
      'libx264',
      '-preset',
      'medium',
      '-crf',
      '${quality.h264Crf}',
      '-pix_fmt',
      'yuv420p',
      if (outputFormat == VideoOutputFormat.mp4 ||
          outputFormat == VideoOutputFormat.mov) ...[
        '-tag:v',
        'avc1',
      ],
    ],
    VideoCodec.hevc => [
      '-c:v',
      'libx265',
      '-preset',
      'medium',
      '-crf',
      '${quality.hevcCrf}',
      '-pix_fmt',
      'yuv420p',
      '-x265-params',
      'log-level=error',
      if (outputFormat == VideoOutputFormat.mp4 ||
          outputFormat == VideoOutputFormat.mov) ...[
        '-tag:v',
        'hvc1',
      ],
    ],
    VideoCodec.mpeg4 => [
      '-c:v',
      'mpeg4',
      '-q:v',
      '${quality.mpeg4Quality}',
      '-pix_fmt',
      'yuv420p',
    ],
  };
}

enum VideoResolution {
  original('原始解析度', null),
  p720('最高 720p', 1280),
  p1080('最高 1080p', 1920),
  p2160('最高 4K', 3840);

  const VideoResolution(this.label, this.maxLongEdge);

  final String label;
  final int? maxLongEdge;

  String? get scaleFilter {
    final edge = maxLongEdge;
    if (edge == null) return null;
    return "scale=w='if(gte(iw,ih),min(iw,$edge),-2)':"
        "h='if(gte(iw,ih),-2,min(ih,$edge))'";
  }

  VideoCodec recommendedCodec(VideoMediaInfo? source) {
    final effectiveLongEdge = maxLongEdge ?? source?.longEdge ?? 0;
    return effectiveLongEdge > 1920 ? VideoCodec.hevc : VideoCodec.h264;
  }

  ({int width, int height})? outputDimensions(VideoMediaInfo? source) {
    final width = source?.width;
    final height = source?.height;
    if (width == null || height == null) return null;
    final edge = maxLongEdge;
    final longEdge = width > height ? width : height;
    if (edge == null || longEdge <= edge) return (width: width, height: height);
    final scale = edge / longEdge;
    int even(int value) => ((value * scale).round() ~/ 2) * 2;
    return (width: even(width), height: even(height));
  }
}

enum VideoQuality {
  high('高畫質', '保留更多細節，檔案較大', 2, 18, 20),
  balanced('標準', '畫質與檔案大小兼顧', 5, 23, 25),
  compact('節省空間', '壓縮較多，適合分享與上傳', 9, 28, 30);

  const VideoQuality(
    this.label,
    this.description,
    this.mpeg4Quality,
    this.h264Crf,
    this.hevcCrf,
  );

  final String label;
  final String description;
  final int mpeg4Quality;
  final int h264Crf;
  final int hevcCrf;
}

final class VideoMediaInfo {
  const VideoMediaInfo({
    required this.container,
    required this.videoCodec,
    required this.audioCodec,
    required this.duration,
    required this.width,
    required this.height,
  });

  final String container;
  final String? videoCodec;
  final String? audioCodec;
  final Duration? duration;
  final int? width;
  final int? height;

  int? get longEdge => width == null || height == null
      ? null
      : width! > height!
      ? width
      : height;
}

sealed class VideoConversionResult {
  const VideoConversionResult();
}

final class VideoConversionProgress {
  const VideoConversionProgress({
    required this.fraction,
    required this.processed,
  });

  final double fraction;
  final Duration processed;
}

double videoConversionFraction({
  required Duration processed,
  required Duration total,
}) {
  if (total <= Duration.zero) return 0;
  return (processed.inMilliseconds / total.inMilliseconds).clamp(0, 0.99);
}

final class VideoConversionSucceeded extends VideoConversionResult {
  const VideoConversionSucceeded(this.path);

  final String path;
}

final class VideoConversionFailed extends VideoConversionResult {
  const VideoConversionFailed(this.reason);

  final String reason;
}

abstract interface class VideoConverter {
  Future<VideoMediaInfo> inspect(String inputPath);

  Future<VideoConversionResult> convert({
    required String inputPath,
    required VideoOutputFormat outputFormat,
    required VideoQuality quality,
    required VideoCodec codec,
    required VideoResolution resolution,
    required Duration? inputDuration,
    void Function(VideoConversionProgress progress)? onProgress,
  });
}
