import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/engagement/easter_egg_catalog.dart';
import 'package:terpsichore/core/video_conversion/video_conversion.dart';
import 'package:terpsichore/entrypoints/mobile/localization/app_text.dart';
import 'package:terpsichore/entrypoints/mobile/localization/english_messages.dart';
import 'package:terpsichore/entrypoints/mobile/localization/english_errors.dart';
import 'package:terpsichore/entrypoints/mobile/screens/ab_analysis_screen.dart';
import 'package:terpsichore/entrypoints/mobile/screens/learning_mode_screen.dart';
import 'package:terpsichore/entrypoints/mobile/screens/music_practice_screen.dart';
import 'package:terpsichore/entrypoints/mobile/screens/notification_settings_screen.dart';
import 'package:terpsichore/entrypoints/mobile/screens/video_conversion_screen.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/saved_project_controls.dart';
import 'package:terpsichore/infrastructure/engagement/easter_egg_service.dart';
import 'package:terpsichore/infrastructure/engagement/emotion_backmail_service.dart';

void main() {
  setUp(() {
    EmotionBackmailService.language.value = AppLanguage.english;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('terpsichore/emotion_backmail'),
          (call) async => call.arguments,
        );
  });
  tearDown(() {
    EmotionBackmailService.language.value = AppLanguage.traditionalChinese;
    EasterEggService.instance.collected.value = const {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('terpsichore/emotion_backmail'),
          null,
        );
  });

  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ValueListenableBuilder<AppLanguage>(
        valueListenable: EmotionBackmailService.language,
        builder: (_, language, _) => MaterialApp(
          scaffoldMessengerKey: EasterEggService.instance.messengerKey,
          locale: language == AppLanguage.english
              ? const Locale('en')
              : const Locale('zh', 'TW'),
          supportedLocales: const [Locale('en'), Locale('zh', 'TW')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('every egg has a complete English translation', () {
    expect(easterEggsEnglish.keys, unorderedEquals(easterEggs.keys));
    for (final egg in easterEggsEnglish.values) {
      for (final field in [egg.title, egg.message, egg.trigger]) {
        expect(field.trim(), isNotEmpty);
        expect(RegExp(r'[\u3400-\u9fff]').hasMatch(field), isFalse);
      }
    }
  });

  test('translations preserve placeholders and user content', () {
    Set<String> placeholders(String text) =>
        RegExp(r'\{\d+\}').allMatches(text).map((m) => m[0]!).toSet();
    for (final entry in englishMessages.entries) {
      expect(
        placeholders(entry.value),
        placeholders(entry.key),
        reason: entry.key,
      );
      expect(entry.value.trim(), isNotEmpty);
    }
    for (final entry in englishErrors.entries) {
      expect(placeholders(entry.value), placeholders(entry.key));
    }
    expect(
      formatAppText('已儲存「{0}」', english: true, arguments: ['舞蹈 {1}.mp4']),
      'Saved “舞蹈 {1}.mp4”',
    );
  });

  test('authored processing errors translate without changing diagnostics', () {
    expect(
      formatAppError(StateError('無法建立所選樂器的練習混音'), english: true),
      'Could not build a practice mix from the selected stems',
    );
    expect(
      formatAppError('影片輸出失敗，FFmpeg 回傳代碼：23', english: true),
      'Video export failed; FFmpeg returned code 23',
    );
    expect(
      formatAppError('音樂轉換失敗：舞蹈 {1}.mp4', english: true),
      'Audio conversion failed: 舞蹈 {1}.mp4',
    );
    expect(
      formatAppError('Native diagnostic 123', english: true),
      'Native diagnostic 123',
    );
  });

  testWidgets('newly discovered eggs also use English dialogue', (
    tester,
  ) async {
    await mount(tester, const SizedBox());
    EasterEggService.instance.engine.trigger('oracleRejected');
    await tester.pumpAndSettle();
    expect(
      find.text(easterEggsEnglish['oracleRejected']!.message),
      findsOneWidget,
    );
    expect(find.text(easterEggs['oracleRejected']!.message), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('existing learning page follows a language change', (
    tester,
  ) async {
    await mount(tester, const LearningModeScreen());
    expect(
      find.text('Choose a dance video to start practicing'),
      findsOneWidget,
    );
    EmotionBackmailService.language.value = AppLanguage.traditionalChinese;
    await tester.pumpAndSettle();
    expect(find.text('選一支舞蹈影片開始練習'), findsOneWidget);
    expect(find.text('Choose a dance video to start practicing'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('music import and stem screen are in English', (tester) async {
    await mount(tester, const MusicPracticeScreen());
    expect(find.text('Music practice'), findsOneWidget);
    expect(find.text('Choose practice music'), findsOneWidget);
    expect(find.text('Import video or audio'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('collected eggs show English details and switch back', (
    tester,
  ) async {
    EasterEggService.instance.collected.value = {'oracleSoundcheck'};
    await mount(tester, const NotificationSettingsScreen());
    final egg = easterEggsEnglish['oracleSoundcheck']!;
    await tester.ensureVisible(find.text(egg.title));
    await tester.tap(find.text(egg.title));
    await tester.pumpAndSettle();
    expect(find.text('Collected easter eggs: 1 / 40'), findsOneWidget);
    expect(find.text(egg.message), findsOneWidget);
    expect(find.text(egg.trigger), findsOneWidget);
    await tester.scrollUntilVisible(find.text('繁體中文'), -200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('繁體中文'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(easterEggs['oracleSoundcheck']!.title),
      200,
    );
    await tester.pumpAndSettle();
    expect(find.text(easterEggs['oracleSoundcheck']!.title), findsOneWidget);
    expect(find.text(easterEggs['oracleSoundcheck']!.message), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('project dialog is translated and preserves entered names', (
    tester,
  ) async {
    await mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => requestProjectName(context, initialValue: '我的舞蹈'),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Save practice project'), findsOneWidget);
    expect(find.text('Project name'), findsOneWidget);
    expect(find.text('我的舞蹈'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('English analysis settings fit $width', (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, const AbAnalysisScreen());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('A · Reference video'), findsOneWidget);
      await tester.tap(find.byTooltip('AI alignment settings'));
      await tester.pumpAndSettle();
      expect(find.text('Search timing and speed'), findsOneWidget);
      expect(find.text('Pose smoothing window (seconds)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Side by side (landscape)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('English conversion dropdowns fit $width and larger text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(
        tester,
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, 850),
            textScaler: const TextScaler.linear(1.3),
          ),
          child: const VideoConversionScreen(),
        ),
      );
      expect(find.text('Video converter'), findsOneWidget);
      final dropdown = find.byType(DropdownButtonFormField<VideoQuality>);
      await tester.scrollUntilVisible(dropdown, 200);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.textContaining('More detail, larger files'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
