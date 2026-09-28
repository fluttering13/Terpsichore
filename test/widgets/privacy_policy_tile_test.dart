import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/privacy_policy_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> mount(WidgetTester tester, {bool english = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PrivacyPolicyTile(english: english)),
      ),
    );
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
  }

  testWidgets('opens the exact policy in an external browser', (tester) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    await mount(tester);
    final launch = calls.singleWhere((call) => call.method == 'launch');
    expect(launch.arguments['url'], privacyPolicyUrl);
    expect(launch.arguments['useWebView'], isFalse);
    expect(launch.arguments['useSafariVC'], isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final throws in [false, true]) {
    testWidgets('browser failure ($throws) leaves a copyable policy link', (
      tester,
    ) async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        if (throws) throw PlatformException(code: 'NO_BROWSER');
        return false;
      });
      String? copied;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = call.arguments['text'] as String;
        }
        return null;
      });
      await mount(tester, english: false);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(privacyPolicyUrl), findsOneWidget);
      await tester.tap(find.text('複製連結'));
      await tester.pumpAndSettle();
      expect(copied, privacyPolicyUrl);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
