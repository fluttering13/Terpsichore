import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/engagement/easter_egg_catalog.dart';
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
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
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
      await eggs.flush();
      final recorded = Map<String, String>.of(eggs.engine.daily);
      expect(await file.exists(), isTrue);
      eggs.engine.daily.clear();
      await eggs.initialize(storageFile: file);
      expect(eggs.engine.daily, recorded);
      await directory.delete(recursive: true);
    });
    await tester.pump();
  });
}
