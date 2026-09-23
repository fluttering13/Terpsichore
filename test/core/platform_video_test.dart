import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/platform_download/platform_video.dart';

void main() {
  test('accepts one Instagram story and rejects story collections', () {
    final link = PlatformVideoLink.parse(
      'https://www.instagram.com/stories/dancer.name/123456789/?igsh=abc',
    );
    expect(link.isInstagramStory, isTrue);
    expect(link.uri.queryParameters['igsh'], 'abc');
    for (final url in [
      'https://www.instagram.com/stories/dancer/',
      'https://www.instagram.com/stories/highlights/123/',
    ]) {
      expect(
        () => PlatformVideoLink.parse(url),
        throwsA(isA<DownloadException>()),
      );
    }
  });
  test('recognizes platform links inside copied share text', () {
    final links = {
      'https://youtu.be/abc123': DownloadPlatform.youtube,
      'https://m.youtube.com/shorts/abc123': DownloadPlatform.youtube,
      'https://www.instagram.com/reel/abc/': DownloadPlatform.instagram,
      'https://m.facebook.com/reel/1234': DownloadPlatform.facebook,
      'https://fb.watch/abc/': DownloadPlatform.facebook,
      'https://www.facebook.com/share/r/18Lvd3oRBQ/': DownloadPlatform.facebook,
      'https://www.threads.net/@dancer/post/abc': DownloadPlatform.threads,
      'https://www.threads.com/share/abc': DownloadPlatform.threads,
    };
    for (final entry in links.entries) {
      expect(
        PlatformVideoLink.parse('看看這段舞蹈 ${entry.key}。').platform,
        entry.value,
      );
    }
  });

  test(
    'rejects fake hosts, credentials, non-video pages and multiple URLs',
    () {
      for (final value in [
        'https://youtube.com.evil.example/watch?v=abc',
        'https://notyoutube.com/watch?v=abc',
        'https://user:password@youtube.com/watch?v=abc',
        'file:///storage/video.mp4',
        'https://www.youtube.com/',
        'https://www.youtube.com/playlist?list=abc',
        'https://www.instagram.com/dancer/',
        'https://www.facebook.com/dancer/',
        'https://www.threads.com/@dancer',
        'https://youtu.be/abc https://youtu.be/def',
        'https://youtu.be:1234/abc',
      ]) {
        expect(
          () => PlatformVideoLink.parse(value),
          throwsA(isA<DownloadException>()),
          reason: value,
        );
      }
    },
  );

  test(
    'unknown resolution is not advertised as HD and silent sources are labeled',
    () {
      const format = PlatformVideoFormat(
        id: '1',
        width: 0,
        height: 0,
        extension: 'mp4',
        silent: true,
      );
      expect(format.label(false), contains('解析度未知'));
      expect(format.label(false), contains('尚未取得音軌'));
      expect(format.label(true), contains('resolution unknown'));
    },
  );

  test('portrait dimensions and video-only size are described accurately', () {
    const format = PlatformVideoFormat(
      id: '2',
      width: 1080,
      height: 1920,
      extension: 'mp4',
      bytes: 10485760,
      mergeAudio: true,
      fps: 30,
      bitrate: 2000,
    );
    expect(format.label(false), contains('1080 × 1920'));
    expect(format.label(false), contains('10.0 MB＋音軌'));
    expect(format.label(false), contains('2000 kbps'));
  });

  test('preserves encoded query parameters in copied video links', () {
    final uri = PlatformVideoLink.parse(
      'https://www.instagram.com/reel/DdiHc3ixAkj/?stkn=NTc4MTIwNjQ2YQ%3D%3D',
    ).uri;
    expect(uri.queryParameters['stkn'], 'NTc4MTIwNjQ2YQ==');
  });
}
