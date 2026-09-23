import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/engagement/easter_egg_catalog.dart';
import 'package:terpsichore/core/platform_download/platform_video.dart';
import 'package:terpsichore/core/saved_projects/saved_project.dart';
import 'package:terpsichore/entrypoints/mobile/screens/home_screen.dart';
import 'package:terpsichore/entrypoints/mobile/screens/notification_settings_screen.dart';
import 'package:terpsichore/entrypoints/mobile/terpsichore_app.dart';
import 'package:terpsichore/infrastructure/engagement/easter_egg_service.dart';
import 'package:terpsichore/infrastructure/engagement/emotion_backmail_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('terpsichore/emotion_backmail');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final eggs = EasterEggService.instance;
  final vibrations = <MethodCall>[];
  setUp(() {
    eggs.foreground = true;
    eggs.collected.value = const <String>{};
    eggs.downloadedPlatforms.clear();
    eggs.projectLastOpened.clear();
    vibrations.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') vibrations.add(call);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          paths,
          (_) async => throw MissingPluginException(),
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => call.arguments);
    eggs.engine.daily.clear();
    // These tests exercise explicit actions, independently of local clock time.
    for (final id in ['night', 'leap', 'april']) {
      eggs.engine.daily[id] = eggs.engine.today;
    }
    eggs.engine.open();
    EmotionBackmailService.language.value = AppLanguage.traditionalChinese;
    EmotionBackmailService.onlineStreak.value = 0;
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: eggs.messengerKey,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('same-video egg waits for return from the native picker', (
    tester,
  ) async {
    await mount(tester, const SizedBox());
    eggs.foreground = false;
    eggs.engine.trigger('duel');
    await tester.pumpAndSettle();
    expect(find.text(easterEggs['duel']!.message), findsNothing);
    expect(vibrations, isEmpty);
    eggs.open();
    await tester.pumpAndSettle();
    expect(find.text(easterEggs['duel']!.message), findsOneWidget);
    expect(vibrations, hasLength(1));
    eggs.showPending();
    await tester.pumpAndSettle();
    expect(vibrations, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ten actual logo taps show the goddess once per session', (
    tester,
  ) async {
    await mount(tester, HomeScreen(onOpenFeature: (_) {}));
    vibrations.clear();
    for (var i = 0; i < 9; i++) {
      await tester.tap(find.byType(Image));
    }
    await tester.pump();
    expect(find.text(easterEggs['logo']!.message), findsNothing);
    expect(vibrations, isEmpty);
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.text(easterEggs['logo']!.message), findsOneWidget);
    expect(find.textContaining(easterEggs['logo']!.title), findsNothing);
    expect(vibrations, hasLength(1));
    await tester.tap(find.byType(Image));
    await tester.pump();
    expect(vibrations, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hundred day long press unlocks the souvenir save action', (
    tester,
  ) async {
    await mount(tester, HomeScreen(onOpenFeature: (_) {}));
    await tester.longPress(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    EmotionBackmailService.onlineStreak.value = 100;
    await tester.pump();
    await tester.longPress(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).title, isNull);
    expect(find.text('儲存紀念圖'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '關閉'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('daily notification toggles use the eleventh real change', (
    tester,
  ) async {
    await mount(tester, const NotificationSettingsScreen());
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byType(Switch));
      await tester.pump();
    }
    expect(find.text(easterEggs['notifications']!.message), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text(easterEggs['notifications']!.message), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching language six times exposes the language egg', (
    tester,
  ) async {
    await mount(tester, const NotificationSettingsScreen());
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text(i.isEven ? 'English' : '繁體中文'));
      await tester.pumpAndSettle();
      if (i < 5) {
        eggs.messengerKey.currentState!.removeCurrentSnackBar();
        await tester.pumpAndSettle();
      }
    }
    // Saved-settings messages are queued before the easter egg.
    eggs.messengerKey.currentState!.removeCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text(easterEggs['language']!.message), findsOneWidget);
    expect(
      EmotionBackmailService.language.value,
      AppLanguage.traditionalChinese,
    );
    // Daily-only storage must not contain session-scoped language counts.
    expect(eggs.engine.daily.containsKey('language'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'third test notification tap collects and displays soundcheck once',
    (tester) async {
      var requests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'testNotification') {
              requests++;
              return false;
            }
            return call.arguments;
          });
      await mount(tester, const NotificationSettingsScreen());
      final button = find.widgetWithText(OutlinedButton, '發送測試通知');
      await tester.ensureVisible(button);
      for (var i = 0; i < 2; i++) {
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(eggs.collected.value, isNot(contains('oracleSoundcheck')));
        eggs.messengerKey.currentState!.removeCurrentSnackBar();
        await tester.pumpAndSettle();
      }
      await tester.tap(button);
      await tester.pumpAndSettle();
      // The scheduling acknowledgement is queued before the easter egg.
      eggs.messengerKey.currentState!.removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(
        find.text(easterEggs['oracleSoundcheck']!.message),
        findsOneWidget,
      );
      expect(eggs.collected.value, contains('oracleSoundcheck'));
      expect(vibrations, hasLength(1));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(requests, 4);
      expect(vibrations, hasLength(1));
      eggs.engine.open();
      expect(eggs.collected.value, contains('oracleSoundcheck'));
      eggs.count('oracleSoundcheck', 3);
      eggs.count('oracleSoundcheck', 3);
      await tester.pump();
      expect(vibrations, hasLength(1));
      eggs.count('oracleSoundcheck', 3);
      await tester.pump();
      expect(vibrations, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('only taps in the blank notification area summon the void egg', (
    tester,
  ) async {
    await mount(tester, const NotificationSettingsScreen());
    final blank = find.byKey(const ValueKey('notification-empty-space'));
    await tester.ensureVisible(blank);
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.tap(blank);
    }
    await tester.pump();
    expect(find.text(easterEggs['void']!.message), findsNothing);
    await tester.tap(blank);
    await tester.pumpAndSettle();
    expect(find.text(easterEggs['void']!.message), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'background and resume clear counters but preserve daily claims',
    (tester) async {
      await tester.pumpWidget(const TerpsichoreApp());
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        eggs.count('notifications', 11);
      }
      eggs.engine.trigger('bones', oncePerDay: true);
      await tester.pumpAndSettle();
      final daily = Map<String, String>.of(eggs.engine.daily);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      eggs.messengerKey.currentState!.clearSnackBars();
      await tester.pumpAndSettle();
      eggs.count('notifications', 11);
      eggs.engine.trigger('bones', oncePerDay: true);
      await tester.pumpAndSettle();
      expect(find.text(easterEggs['notifications']!.message), findsNothing);
      expect(find.text(easterEggs['bones']!.message), findsNothing);
      expect(eggs.engine.daily, daily);
      for (var i = 0; i < 10; i++) {
        eggs.count('notifications', 11);
      }
      await tester.pumpAndSettle();
      expect(find.text(easterEggs['notifications']!.message), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('daily claims really survive writing and reloading storage', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'terpsichore-eggs-',
      );
      final file = File('${directory.path}/daily.json');
      await eggs.initialize(storageFile: file);
      eggs.engine.trigger('bones', oncePerDay: true);
      await eggs.flush();
      eggs.engine.trigger('unseal', oncePerDay: true);
      eggs.engine.trigger('logo');
      await eggs.flush();
      final recorded = Map<String, String>.of(eggs.engine.daily);
      final collected = Set<String>.of(eggs.collected.value);
      expect(await file.exists(), isTrue);
      eggs.engine.daily.clear();
      eggs.collected.value = const <String>{};
      await eggs.initialize(storageFile: file);
      expect(eggs.engine.daily, recorded);
      expect(eggs.collected.value, collected);
      expect(eggs.collected.value, contains('logo'));
      await directory.delete(recursive: true);
    });
    await tester.pump();
  });

  testWidgets('legacy daily records become collected eggs', (tester) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('legacy-eggs-');
      final file = File('${directory.path}/easter_eggs.json');
      await file.writeAsString(jsonEncode({'bones': '2026-9-1'}));
      await eggs.initialize(storageFile: file);
      expect(eggs.collected.value, {'bones'});
      await directory.delete(recursive: true);
    });
  });

  testWidgets('platform collection and project visits survive restart', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('feature-eggs-');
      final file = File('${directory.path}/easter_eggs.json');
      await eggs.initialize(storageFile: file);
      for (final platform in DownloadPlatform.values.take(3)) {
        eggs.downloadCompleted(platform);
        eggs.downloadCompleted(platform);
      }
      expect(eggs.collected.value, isNot(contains('collector')));
      final old = DateTime.now().subtract(const Duration(days: 40));
      final project = SavedProject(
        id: 'old-project',
        name: 'Old dance',
        mode: SavedProjectMode.learning,
        createdAt: old,
        updatedAt: old,
        data: {},
      );
      eggs.projectLoaded('learning', project);
      expect(eggs.collected.value, isNot(contains('reunion')));
      eggs.engine.projectPlayback('learning');
      expect(eggs.collected.value, contains('reunion'));
      await eggs.flush();
      eggs.downloadedPlatforms.clear();
      eggs.projectLastOpened.clear();
      eggs.collected.value = const <String>{};
      await eggs.initialize(storageFile: file);
      expect(eggs.downloadedPlatforms.length, 3);
      expect(eggs.projectLastOpened, contains('old-project'));
      eggs.downloadCompleted(DownloadPlatform.threads);
      expect(eggs.collected.value, contains('collector'));
      eggs.engine.open();
      eggs.collected.value = const <String>{};
      eggs.projectLoaded('learning', project);
      eggs.engine.projectPlayback('learning');
      expect(eggs.collected.value, isNot(contains('reunion')));
      await eggs.flush();
      await directory.delete(recursive: true);
    });
    await tester.pump();
  });

  testWidgets('settings show only collected eggs with dialogue and trigger', (
    tester,
  ) async {
    await mount(tester, const NotificationSettingsScreen());
    await tester.ensureVisible(find.text('已收集的彩蛋：0 / 40'));
    expect(find.text('尚未收集到彩蛋，繼續探索與練習來發現吧！'), findsOneWidget);
    eggs.collected.value = {'logo'};
    await tester.pumpAndSettle();
    final title = find.text(easterEggs['logo']!.title);
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(find.text(easterEggs['logo']!.message), findsOneWidget);
    expect(find.text(easterEggs['logo']!.trigger), findsOneWidget);
    expect(find.text(easterEggs['night']!.title), findsNothing);
    eggs.engine.open();
    expect(eggs.collected.value, contains('logo'));
    await tester.pumpWidget(const SizedBox());
  });
}
