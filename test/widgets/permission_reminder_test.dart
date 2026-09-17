import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/permission_reminder.dart';
import 'package:terpsichore/infrastructure/engagement/emotion_backmail_service.dart';

void main() {
  const channel = MethodChannel('terpsichore/emotion_backmail');
  setUp(() {
    EmotionBackmailService.notificationSettings.value =
        const NotificationSettings();
    EmotionBackmailService.language.value = AppLanguage.traditionalChinese;
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    EmotionBackmailService.notificationSettings.value =
        const NotificationSettings();
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PermissionReminder(child: Scaffold(body: Text('home'))),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('granted and deliberately disabled reminders do not prompt', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byType(AlertDialog), findsNothing);
    EmotionBackmailService.notificationSettings.value =
        const NotificationSettings(
          enabled: false,
          notificationsAllowed: false,
          exactAlarmAllowed: false,
        );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('missing notification prompts only once per session', (
    tester,
  ) async {
    await mount(tester);
    EmotionBackmailService.notificationSettings.value =
        const NotificationSettings(notificationsAllowed: false);
    await tester.pumpAndSettle();
    expect(find.text('前往通知設定'), findsOneWidget);
    await tester.tap(find.text('稍後再說'));
    await tester.pumpAndSettle();
    EmotionBackmailService.notificationSettings.value =
        const NotificationSettings(channelAllowed: false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('routes both permission types and refreshes when granted', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    EmotionBackmailService.notificationSettings.value =
        const NotificationSettings(
          channelAllowed: false,
          exactAlarmAllowed: false,
        );
    await mount(tester);
    await tester.tap(find.text('前往通知設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('前往鬧鐘與提醒設定'));
    await tester.pumpAndSettle();
    expect(calls, ['openNotificationSettings', 'requestExactAlarmPermission']);
    EmotionBackmailService.notificationSettings.value =
        const NotificationSettings();
    await tester.pumpAndSettle();
    expect(find.text('前往通知設定'), findsNothing);
    expect(find.text('完成'), findsOneWidget);
  });
  testWidgets('settings failure is recoverable', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'SETTINGS_UNAVAILABLE');
        });
    EmotionBackmailService.notificationSettings.value =
        const NotificationSettings(notificationsAllowed: false);
    await mount(tester);
    await tester.tap(find.text('前往通知設定'));
    await tester.pumpAndSettle();
    expect(find.text('無法開啟設定，請手動前往系統的 Terpsichore 設定。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
