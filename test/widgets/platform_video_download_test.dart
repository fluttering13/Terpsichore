import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/platform_download/platform_video.dart';
import 'package:terpsichore/entrypoints/mobile/screens/platform_video_download_screen.dart';
import 'package:terpsichore/infrastructure/engagement/emotion_backmail_service.dart';
import 'package:terpsichore/infrastructure/engagement/easter_egg_service.dart';
import 'package:terpsichore/infrastructure/platform_download/instagram_session.dart';

const _formats = [
  PlatformVideoFormat(id: 'high', width: 1920, height: 1080, extension: 'mp4'),
  PlatformVideoFormat(id: 'low', width: 640, height: 360, extension: 'mp4'),
];
const _video = PlatformVideo(
  snapshotId: 'test',
  title: '舞蹈測試影片',
  formats: _formats,
);

final class FakeDownloader implements PlatformVideoDownloader {
  final updates = StreamController<DownloadProgress>.broadcast();
  DownloadException? inspectError;
  DownloadException? downloadError;
  Completer<PlatformVideo>? pendingInspection;
  Completer<DownloadReceipt>? pendingDownload;
  String? activeJobId;
  String? selectedId;
  String? cancelledId;
  int downloads = 0;
  int inspections = 0;
  PlatformVideo resultVideo = _video;
  List<int>? selectedPages;
  bool? combined;
  @override
  Stream<DownloadProgress> get progress => updates.stream;
  @override
  Future<PlatformVideo> inspect(String url, String jobId) async {
    inspections++;
    activeJobId = jobId;
    if (inspectError != null) throw inspectError!;
    return pendingInspection?.future ?? resultVideo;
  }

  @override
  Future<DownloadReceipt> download(
    PlatformVideo video,
    PlatformVideoFormat format,
    String jobId,
  ) async {
    downloads++;
    activeJobId = jobId;
    selectedId = format.id;
    if (downloadError != null) throw downloadError!;
    if (pendingDownload != null) return pendingDownload!.future;
    return const DownloadReceipt(
      'content://download/1',
      'Download/Terpsichore/test.mp4',
    );
  }

  @override
  Future<DownloadReceipt> downloadSelection(
    List<PlatformVideo> videos,
    List<PlatformVideoFormat> formats,
    String jobId, {
    required bool combine,
  }) async {
    selectedPages = videos.map((video) => video.page).toList();
    combined = combine;
    return download(videos.first, formats.first, jobId);
  }

  @override
  Future<void> cancel(String jobId) async {
    cancelledId = jobId;
    pendingInspection?.completeError(const DownloadException('CANCELLED'));
  }
}

final class FakeInstagramSession implements InstagramSession {
  bool present = false;
  bool success = true;
  bool? imported;
  int prompts = 0;
  @override
  Future<bool> hasSession() async => present;
  @override
  Future<bool> authenticate({
    required bool importFile,
    required bool english,
  }) async {
    prompts++;
    imported = importFile;
    if (success) present = true;
    return success;
  }

  @override
  Future<void> clear() async {
    present = false;
  }
}

Future<void> showStory(
  WidgetTester tester,
  FakeDownloader downloader,
  FakeInstagramSession session,
) async {
  addTearDown(downloader.updates.close);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlatformVideoDownloadScreen(
          downloader: downloader,
          instagramSession: session,
        ),
      ),
    ),
  );
  await tester.enterText(
    find.byKey(const ValueKey('platform-video-link')),
    'https://www.instagram.com/stories/dancer/123456/',
  );
  await tester.tap(find.text('解析影片'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final combine in [false, true]) {
    testWidgets(
      'carousel selected pages with combine=$combine on narrow screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final downloader = FakeDownloader()
          ..resultVideo = PlatformVideo(
            snapshotId: 'post',
            title: 'Nine videos',
            formats: _formats,
            entries: [
              for (var page = 1; page <= 9; page++)
                PlatformVideo(
                  snapshotId: 'page-$page',
                  title: 'Video $page',
                  page: page,
                  formats: _formats,
                ),
            ],
          );
        await showStory(
          tester,
          downloader,
          FakeInstagramSession()..present = true,
        );
        await tester.pumpAndSettle();
        Future<void> tapText(String text) async {
          await tester.ensureVisible(find.text(text));
          await tester.pumpAndSettle();
          await tester.tap(find.text(text));
          await tester.pumpAndSettle();
        }

        await tapText('取消全選');
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, '下載選取的 0 支影片'),
              )
              .onPressed,
          isNull,
        );
        await tapText('第 2 頁');
        await tapText('第 7 頁');
        if (combine) await tapText('合成一支影片');
        await tapText(combine ? '合成選取的 2 支影片' : '下載選取的 2 支影片');
        expect(downloader.selectedPages, [2, 7]);
        expect(downloader.combined, combine);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('carousel selects every video by default', (tester) async {
    final downloader = FakeDownloader()
      ..resultVideo = PlatformVideo(
        snapshotId: 'post',
        title: 'Nine videos',
        formats: _formats,
        entries: [
          for (var page = 1; page <= 9; page++)
            PlatformVideo(
              snapshotId: 'page-$page',
              title: 'Video $page',
              page: page,
              formats: _formats,
            ),
        ],
      );
    await showStory(tester, downloader, FakeInstagramSession()..present = true);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('下載選取的 9 支影片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下載選取的 9 支影片'));
    await tester.pumpAndSettle();
    expect(downloader.selectedPages, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(downloader.combined, false);
  });

  testWidgets(
    'carousel advances phase for each page and reports permission failures',
    (tester) async {
      final downloader = FakeDownloader()
        ..pendingDownload = Completer<DownloadReceipt>()
        ..resultVideo = const PlatformVideo(
          snapshotId: 'post',
          title: 'Post',
          formats: _formats,
          entries: [
            PlatformVideo(
              snapshotId: 'one',
              title: 'One',
              page: 1,
              formats: _formats,
            ),
            PlatformVideo(
              snapshotId: 'two',
              title: 'Two',
              page: 2,
              formats: _formats,
            ),
          ],
        );
      await showStory(
        tester,
        downloader,
        FakeInstagramSession()..present = true,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('下載選取的 2 支影片'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下載選取的 2 支影片'));
      await tester.pump();
      downloader.updates.add(
        DownloadProgress(
          downloader.activeJobId!,
          'saving',
          0.49,
          item: 1,
          total: 2,
        ),
      );
      await tester.pump();
      downloader.updates.add(
        DownloadProgress(
          downloader.activeJobId!,
          'downloading',
          0.51,
          item: 2,
          total: 2,
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('第 2／2 支影片'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('正在下載影片…'), findsOneWidget);
      expect(find.text('整體進度 51%'), findsOneWidget);
      downloader.pendingDownload!.complete(
        const DownloadReceipt(
          'content://saved',
          'Saved page 1',
          issues: ['2:IG_ACCESS_DENIED'],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('下載結果：有項目需要確認'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved page 1'), findsOneWidget);
      expect(find.textContaining('第 2 頁：'), findsOneWidget);
      expect(find.text('下載完成'), findsNothing);
    },
  );

  setUp(() => EasterEggService.instance.downloadedPlatforms.clear());
  testWidgets('clearing session removes the story preview', (tester) async {
    final downloader = FakeDownloader();
    final session = FakeInstagramSession()..present = true;
    await showStory(tester, downloader, session);
    await tester.pumpAndSettle();
    expect(find.text('舞蹈測試影片'), findsOneWidget);
    await tester.tap(find.text('清除 IG 登入狀態'));
    await tester.pumpAndSettle();
    expect(session.present, isFalse);
    expect(find.text('下載到本機'), findsNothing);
  });

  testWidgets('permission lost at download time also notifies the user', (
    tester,
  ) async {
    final downloader = FakeDownloader()
      ..downloadError = const DownloadException('IG_ACCESS_DENIED');
    final session = FakeInstagramSession()..present = true;
    await showStory(tester, downloader, session);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('下載到本機'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下載到本機'));
    await tester.pumpAndSettle();
    expect(downloader.downloads, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('尚未獲准追蹤'), findsWidgets);
    expect(find.text('下載完成'), findsNothing);
    expect(EasterEggService.instance.downloadedPlatforms, isEmpty);
  });

  for (final importFile in [false, true]) {
    testWidgets('story requires session before preview, import=$importFile', (
      tester,
    ) async {
      final downloader = FakeDownloader();
      final session = FakeInstagramSession();
      await showStory(tester, downloader, session);
      expect(downloader.inspections, 0);
      expect(find.text('需要 Instagram 登入狀態'), findsOneWidget);
      await tester.tap(find.text(importFile ? '匯入登入狀態' : '登入 Instagram'));
      await tester.pumpAndSettle();
      expect(session.imported, importFile);
      expect(downloader.inspections, 1);
      expect(downloader.downloads, 0);
      expect(find.text('舞蹈測試影片'), findsOneWidget);
    });
  }

  testWidgets('cancelled sign-in does not inspect or download', (tester) async {
    final downloader = FakeDownloader();
    final session = FakeInstagramSession()..success = false;
    await showStory(tester, downloader, session);
    await tester.tap(find.text('登入 Instagram'));
    await tester.pumpAndSettle();
    expect(downloader.inspections, 0);
    expect(downloader.downloads, 0);
    expect(find.text('下載到本機'), findsNothing);
  });

  testWidgets(
    'denied story notifies user without retrying login automatically',
    (tester) async {
      final downloader = FakeDownloader()
        ..inspectError = const DownloadException('IG_ACCESS_DENIED');
      final session = FakeInstagramSession()..present = true;
      await showStory(tester, downloader, session);
      await tester.pumpAndSettle();
      expect(session.prompts, 0);
      expect(downloader.inspections, 1);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('尚未獲准追蹤'), findsWidgets);
      expect(find.text('下載到本機'), findsNothing);
    },
  );
  testWidgets('quality picker fits a narrow phone with enlarged English text', (
    tester,
  ) async {
    final service = FakeDownloader();
    addTearDown(service.updates.close);
    final previousLanguage = EmotionBackmailService.language.value;
    EmotionBackmailService.language.value = AppLanguage.english;
    addTearDown(() => EmotionBackmailService.language.value = previousLanguage);
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 780),
            textScaler: TextScaler.linear(1.4),
          ),
          child: Scaffold(
            body: PlatformVideoDownloadScreen(downloader: service),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('platform-video-link')),
      'https://youtu.be/test',
    );
    await tester.tap(find.text('Analyze video'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(
      find.byType(DropdownButtonFormField<String>).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  Future<void> show(WidgetTester tester, FakeDownloader service) async {
    addTearDown(service.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlatformVideoDownloadScreen(downloader: service)),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('platform-video-link')),
      'https://youtu.be/test',
    );
  }

  testWidgets('inspection shows activity and changing stage messages', (
    tester,
  ) async {
    final service = FakeDownloader()
      ..pendingInspection = Completer<PlatformVideo>();
    await show(tester, service);
    await tester.tap(find.text('解析影片'));
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    expect(find.text('正在準備影片服務…'), findsOneWidget);
    service.updates.add(
      DownloadProgress(service.activeJobId!, 'metadata', null),
    );
    await tester.pump();
    expect(find.text('正在讀取影片與音軌資料…'), findsOneWidget);
    service.updates.add(
      DownloadProgress(service.activeJobId!, 'connecting', null),
    );
    await tester.pump();
    expect(find.text('正在讀取影片與音軌資料…'), findsOneWidget);
    service.updates.add(
      DownloadProgress(service.activeJobId!, 'formats', null),
    );
    await tester.pump();
    expect(find.text('正在整理可下載的畫質與解析度…'), findsOneWidget);
    service.pendingInspection!.complete(_video);
    await tester.pumpAndSettle();
  });

  testWidgets('download progress stays determinate and never moves backwards', (
    tester,
  ) async {
    final service = FakeDownloader()
      ..pendingDownload = Completer<DownloadReceipt>();
    await show(tester, service);
    await tester.tap(find.text('解析影片'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('下載到本機'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下載到本機'));
    await tester.pump();
    await tester.scrollUntilVisible(find.byType(LinearProgressIndicator), -200);
    await tester.pumpAndSettle();
    Future<void> update(String phase, double? fraction, {String? job}) async {
      service.updates.add(
        DownloadProgress(job ?? service.activeJobId!, phase, fraction),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    double? value() => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value;
    await update('downloading', 0.45);
    expect(value(), closeTo(0.45, 0.001));
    await update('audio', 0.1);
    expect(value(), closeTo(0.45, 0.001));
    await update('audio', double.nan);
    await update('audio', null);
    await update('saving', 0.99, job: 'old-job');
    expect(value(), closeTo(0.45, 0.001));
    await update('merging', 0.9);
    expect(find.text('正在合併影片與音軌…'), findsOneWidget);
    await update('saving', 0.95);
    expect(value(), closeTo(0.95, 0.001));
    await update('downloading', 0.5);
    expect(find.text('正在儲存到本機…'), findsOneWidget);
    expect(value(), closeTo(0.95, 0.001));
    service.pendingDownload!.complete(
      const DownloadReceipt('content://1', 'test.mp4'),
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'selects actual quality and downloads only on explicit download tap',
    (tester) async {
      final service = FakeDownloader();
      await show(tester, service);
      await tester.tap(find.text('解析影片'));
      await tester.pumpAndSettle();
      expect(service.downloads, 0);
      expect(find.text('舞蹈測試影片'), findsOneWidget);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('640 × 360').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('下載到本機'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下載到本機'));
      await tester.pumpAndSettle();
      expect(service.selectedId, 'low');
      expect(EasterEggService.instance.downloadedPlatforms, {'youtube'});
      await tester.ensureVisible(find.text('下載完成'));
      await tester.pumpAndSettle();
      expect(find.text('Download/Terpsichore/test.mp4'), findsOneWidget);
    },
  );

  testWidgets('warns about restricted access before any download is offered', (
    tester,
  ) async {
    final service = FakeDownloader()
      ..inspectError = const DownloadException('ACCESS_RESTRICTED');
    await show(tester, service);
    await tester.tap(find.text('解析影片'));
    await tester.pumpAndSettle();
    expect(find.textContaining('可能非公開'), findsOneWidget);
    expect(find.text('下載到本機'), findsNothing);
    expect(service.downloads, 0);
  });

  testWidgets('editing the link invalidates old download choices', (
    tester,
  ) async {
    final service = FakeDownloader();
    await show(tester, service);
    await tester.tap(find.text('解析影片'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('platform-video-link')),
      'https://fb.watch/other',
    );
    await tester.pump();
    expect(find.text('舞蹈測試影片'), findsNothing);
    expect(find.text('下載到本機'), findsNothing);
  });

  testWidgets('cancels inspection and allows retry without a stale preview', (
    tester,
  ) async {
    final service = FakeDownloader()
      ..pendingInspection = Completer<PlatformVideo>();
    await show(tester, service);
    await tester.tap(find.text('解析影片'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.cancelledId, isNotNull);
    expect(find.text('已取消。'), findsOneWidget);
    expect(find.text('下載到本機'), findsNothing);
    service.pendingInspection = null;
    await tester.tap(find.text('解析影片'));
    await tester.pumpAndSettle();
    expect(find.text('舞蹈測試影片'), findsOneWidget);
  });
}
