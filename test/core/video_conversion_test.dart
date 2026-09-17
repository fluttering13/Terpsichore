import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/video_conversion/video_conversion.dart';

void main() {
  const fourKPortrait = VideoMediaInfo(
    container: 'MOV',
    videoCodec: 'HEVC',
    audioCodec: 'AAC',
    duration: Duration(seconds: 30),
    width: 2160,
    height: 3840,
  );

  test('video output formats expose the expected extension and MIME type', () {
    expect(VideoOutputFormat.mp4.extension, 'mp4');
    expect(VideoOutputFormat.mov.mimeType, 'video/quicktime');
    expect(VideoOutputFormat.mkv.extension, 'mkv');
    expect(VideoOutputFormat.avi.mimeType, 'video/x-msvideo');
  });

  test('resolution recommends a compatible codec', () {
    expect(
      VideoResolution.p720.recommendedCodec(fourKPortrait),
      VideoCodec.h264,
    );
    expect(
      VideoResolution.p1080.recommendedCodec(fourKPortrait),
      VideoCodec.h264,
    );
    expect(
      VideoResolution.p2160.recommendedCodec(fourKPortrait),
      VideoCodec.hevc,
    );
    expect(
      VideoResolution.original.recommendedCodec(fourKPortrait),
      VideoCodec.hevc,
    );
  });

  test('resolution preserves portrait aspect ratio without upscaling', () {
    expect(VideoResolution.p1080.outputDimensions(fourKPortrait), (
      width: 1080,
      height: 1920,
    ));
    expect(VideoResolution.p2160.outputDimensions(fourKPortrait), (
      width: 2160,
      height: 3840,
    ));
  });

  test('MP4 H.264 uses x264 and quality-specific CRF', () {
    final arguments = VideoOutputFormat.mp4.encodingArguments(
      quality: VideoQuality.balanced,
      codec: VideoCodec.h264,
      resolution: VideoResolution.p1080,
    );

    expect(arguments, containsAllInOrder(['-c:v', 'libx264']));
    expect(arguments, containsAllInOrder(['-crf', '23']));
    expect(arguments, containsAllInOrder(['-tag:v', 'avc1']));
    expect(arguments, contains('-vf'));
  });

  test('4K HEVC uses x265 and hvc1 for Apple compatibility', () {
    final arguments = VideoOutputFormat.mp4.encodingArguments(
      quality: VideoQuality.high,
      codec: VideoCodec.hevc,
      resolution: VideoResolution.p2160,
    );

    expect(arguments, containsAllInOrder(['-c:v', 'libx265']));
    expect(arguments, containsAllInOrder(['-crf', '20']));
    expect(arguments, containsAllInOrder(['-tag:v', 'hvc1']));
  });

  test('AVI only offers legacy MPEG-4', () {
    expect(VideoOutputFormat.avi.supportedCodecs, [VideoCodec.mpeg4]);
  });

  test('conversion progress follows processed media time and caps at 99%', () {
    expect(
      videoConversionFraction(
        processed: const Duration(seconds: 15),
        total: const Duration(seconds: 60),
      ),
      0.25,
    );
    expect(
      videoConversionFraction(
        processed: const Duration(seconds: 90),
        total: const Duration(seconds: 60),
      ),
      0.99,
    );
    expect(
      videoConversionFraction(
        processed: const Duration(seconds: 1),
        total: Duration.zero,
      ),
      0,
    );
  });
}
