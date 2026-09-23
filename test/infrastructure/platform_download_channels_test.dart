import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/platform_download/platform_video.dart';
import 'package:terpsichore/infrastructure/platform_download/instagram_session.dart';
import 'package:terpsichore/infrastructure/platform_download/native_platform_video_downloader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const downloads = MethodChannel('terpsichore/platform_download');
  const sessions = MethodChannel('terpsichore/instagram_session');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const downloader = NativePlatformVideoDownloader();
  const session = NativeInstagramSession();
  const format = PlatformVideoFormat(
    id: 'high',
    width: 1080,
    height: 1920,
    extension: 'mp4',
  );
  const video = PlatformVideo(
    snapshotId: 'snapshot',
    title: 'Dance',
    formats: [format],
  );
  Matcher errorCode(String code) => throwsA(
    isA<DownloadException>().having((error) => error.code, 'code', code),
  );

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    messenger.setMockMethodCallHandler(downloads, null);
    messenger.setMockMethodCallHandler(sessions, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'inspection preserves carousel pages and native format metadata',
    () async {
      messenger.setMockMethodCallHandler(downloads, (call) async {
        expect(call.method, 'inspect');
        expect(call.arguments, {'url': 'https://youtu.be/abc', 'jobId': 'job'});
        return {
          'snapshotId': 'root',
          'title': 'Carousel',
          'formats': [],
          'entries': [
            {
              'snapshotId': 'page-2',
              'title': 'Second',
              'page': 2,
              'thumbnailUrl': 'https://example.com/thumbnail.jpg',
              'formats': [
                {
                  'id': 'high',
                  'extension': 'mp4',
                  'width': 1080,
                  'height': 1920,
                  'fps': 29.97,
                  'bitrate': 2000,
                  'bytes': 1048576,
                  'mergeAudio': true,
                  'silent': false,
                },
              ],
            },
          ],
        };
      });
      final result = await downloader.inspect('https://youtu.be/abc', 'job');
      expect(result.snapshotId, 'root');
      final page = result.entries.single;
      expect(page.page, 2);
      expect(page.snapshotId, 'page-2');
      expect(page.thumbnailUrl, 'https://example.com/thumbnail.jpg');
      final selected = page.formats.single;
      expect(selected.width, 1080);
      expect(selected.height, 1920);
      expect(selected.fps, 29.97);
      expect(selected.bytes, 1048576);
      expect(selected.bitrate, 2000);
      expect(selected.mergeAudio, isTrue);
      expect(selected.silent, isFalse);
    },
  );

  test(
    'single download and cancellation use the active job and snapshot',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(downloads, (call) async {
        calls.add(call);
        return call.method == 'download'
            ? {'uri': 'content://downloads/1', 'location': 'Download/Dance.mp4'}
            : null;
      });
      final receipt = await downloader.download(video, format, 'job');
      await downloader.cancel('job');
      expect(receipt.uri, 'content://downloads/1');
      expect(receipt.location, 'Download/Dance.mp4');
      expect(calls.map((call) => call.method), ['download', 'cancel']);
      expect(calls.first.arguments, {
        'snapshotId': 'snapshot',
        'formatId': 'high',
        'jobId': 'job',
      });
      expect(calls.last.arguments, {'jobId': 'job'});
    },
  );

  for (final combine in [false, true]) {
    test(
      'batch download preserves page/format pairing with combine=$combine',
      () async {
        const second = PlatformVideo(
          snapshotId: 'second',
          title: '',
          formats: [],
        );
        const low = PlatformVideoFormat(
          id: 'low',
          width: 640,
          height: 360,
          extension: 'mp4',
        );
        messenger.setMockMethodCallHandler(downloads, (call) async {
          expect(call.method, 'downloadSelection');
          expect(call.arguments, {
            'jobId': 'batch',
            'combine': combine,
            'items': [
              {'snapshotId': 'snapshot', 'formatId': 'high'},
              {'snapshotId': 'second', 'formatId': 'low'},
            ],
          });
          return {
            'issues': ['Page 2: NO_VIDEO'],
          };
        });
        final receipt = await downloader.downloadSelection(
          [video, second],
          [format, low],
          'batch',
          combine: combine,
        );
        expect(receipt.issues, ['Page 2: NO_VIDEO']);
        expect(receipt.uri, isEmpty);
        expect(receipt.location, isEmpty);
      },
    );
  }

  test('unsupported platforms reject calls and expose no progress', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(downloads, (_) async {
      fail('Unsupported platforms must not call the native downloader');
    });
    await expectLater(
      downloader.inspect('url', 'job'),
      errorCode('UNSUPPORTED_PLATFORM'),
    );
    expect(await downloader.progress.toList(), isEmpty);
  });

  test('native errors preserve actionable download and login codes', () async {
    messenger.setMockMethodCallHandler(downloads, (_) async {
      throw PlatformException(code: 'EXPIRED');
    });
    messenger.setMockMethodCallHandler(sessions, (_) async {
      throw PlatformException(code: 'IG_INVALID_COOKIES');
    });
    await expectLater(
      downloader.download(video, format, 'job'),
      errorCode('EXPIRED'),
    );
    await expectLater(
      session.authenticate(importFile: true, english: false),
      errorCode('IG_INVALID_COOKIES'),
    );
  });

  test('missing native plugins become unsupported-platform errors', () async {
    await expectLater(
      downloader.inspect('url', 'job'),
      errorCode('UNSUPPORTED_PLATFORM'),
    );
    await expectLater(session.hasSession(), errorCode('UNSUPPORTED_PLATFORM'));
  });

  test(
    'session status, login, import and clear preserve user choices',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(sessions, (call) async {
        calls.add(call);
        return call.method == 'clear' ? null : true;
      });
      expect(await session.hasSession(), isTrue);
      expect(
        await session.authenticate(importFile: false, english: true),
        isTrue,
      );
      expect(
        await session.authenticate(importFile: true, english: false),
        isTrue,
      );
      await session.clear();
      expect(calls.map((call) => call.method), [
        'status',
        'authenticate',
        'authenticate',
        'clear',
      ]);
      expect(calls[1].arguments, {'mode': 'login', 'english': true});
      expect(calls[2].arguments, {'mode': 'import', 'english': false});
    },
  );

  test('null session responses do not report a successful login', () async {
    messenger.setMockMethodCallHandler(sessions, (_) async => null);
    expect(await session.hasSession(), isFalse);
    expect(
      await session.authenticate(importFile: false, english: true),
      isFalse,
    );
  });
}
