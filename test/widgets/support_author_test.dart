import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/support/support_config.dart';
import 'package:terpsichore/infrastructure/engagement/emotion_backmail_service.dart';
import 'package:terpsichore/infrastructure/support/support_store.dart';
import 'package:terpsichore/entrypoints/mobile/screens/support_author_screen.dart';

class FakeStore extends ChangeNotifier implements SupportStore {
  @override
  SupportStoreStatus status = SupportStoreStatus.ready;
  final owned = <SupportItem>{};
  final bought = <SupportItem>[];
  @override
  bool useTheme = false;
  @override
  void selectTheme(bool value) {
    useTheme = value;
    notifyListeners();
  }

  @override
  bool owns(SupportItem item) => owned.contains(item);
  @override
  String? priceFor(SupportItem item) => status == SupportStoreStatus.unavailable
      ? null
      : item == SupportItem.badge
      ? 'NT\$90'
      : 'NT\$150';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> buy(SupportItem item) async {
    bought.add(item);
  }

  @override
  Future<void> restore() async {}
}

void main() {
  late FakeStore store;
  setUp(() {
    store = FakeStore();
    EmotionBackmailService.language.value = AppLanguage.english;
  });
  tearDown(() {
    store.dispose();
    EmotionBackmailService.language.value = AppLanguage.traditionalChinese;
  });
  Future<void> mount(
    WidgetTester tester, {
    SupportConfig config = const SupportConfig(),
    Future<bool> Function(Uri)? launch,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SupportAuthorScreen(
          config: config,
          store: store,
          openPayment: launch ?? (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Play displays separate live prices and hides external routes', (
    tester,
  ) async {
    await mount(
      tester,
      config: const SupportConfig(
        ecpayUrl: 'https://p.ecpay.com.tw/123',
        coffeeUrl: 'https://buymeacoffee.com/creator',
      ),
    );
    expect(find.text('Purchase · NT\$90'), findsOneWidget);
    await tester.ensureVisible(find.text('Purchase · NT\$90'));
    await tester.tap(find.text('Purchase · NT\$90'));
    await tester.scrollUntilVisible(find.text('Purchase · NT\$150'), 250);
    await tester.tap(find.text('Purchase · NT\$150'));
    expect(store.bought, [SupportItem.badge, SupportItem.theme]);
    expect(find.text('Buy Me a Coffee'), findsNothing);
    expect(find.text('ECPay · Taiwan'), findsNothing);
  });

  testWidgets(
    'both external channels open exact configured links without granting rewards',
    (tester) async {
      final launched = <Uri>[];
      await mount(
        tester,
        config: const SupportConfig(
          distribution: SupportDistribution.direct,
          ecpayUrl: 'https://p.ecpay.com.tw/123',
          coffeeUrl: 'https://buymeacoffee.com/creator',
        ),
        launch: (uri) async {
          launched.add(uri);
          return true;
        },
      );
      final buttons = find.widgetWithText(OutlinedButton, 'Open support page');
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(buttons.at(i));
        await tester.tap(buttons.at(i));
        await tester.pumpAndSettle();
      }
      expect(launched.map((u) => u.toString()), [
        'https://p.ecpay.com.tw/123',
        'https://buymeacoffee.com/creator',
      ]);
      expect(store.owned, isEmpty);
      expect(store.bought, isEmpty);
    },
  );

  testWidgets('missing configuration never opens a checkout', (tester) async {
    store.status = SupportStoreStatus.unavailable;
    await mount(
      tester,
      config: const SupportConfig(
        playEcpayAllowed: true,
        playCoffeeAllowed: true,
      ),
      launch: (_) async {
        fail('Unconfigured links must stay disabled');
      },
    );
    expect(
      tester
          .widgetList<FilledButton>(find.byType(FilledButton))
          .every((b) => b.onPressed == null),
      isTrue,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .every((b) => b.onPressed == null),
      isTrue,
    );
    expect(store.bought, isEmpty);
  });

  testWidgets(
    'external launch failure offers an error without claiming payment',
    (tester) async {
      await mount(
        tester,
        config: const SupportConfig(
          distribution: SupportDistribution.direct,
          ecpayUrl: 'https://p.ecpay.com.tw/123',
        ),
        launch: (_) async => false,
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Open support page').first,
      );
      await tester.pump();
      expect(
        find.text('Unable to open the payment page. Please try again.'),
        findsOneWidget,
      );
      expect(store.owned, isEmpty);
    },
  );

  testWidgets(
    'owned theme exposes the color switch and cannot be bought twice',
    (tester) async {
      store.owned.add(SupportItem.theme);
      await mount(tester);
      await tester.scrollUntilVisible(find.byType(SwitchListTile), 250);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(store.useTheme, isTrue);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Owned'))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('support-theme-owned')), findsOneWidget);
    },
  );

  testWidgets('all channels fit a narrow screen in Chinese and English', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(
      tester,
      config: const SupportConfig(
        playEcpayAllowed: true,
        playCoffeeAllowed: true,
      ),
    );
    for (final language in [
      AppLanguage.english,
      AppLanguage.traditionalChinese,
    ]) {
      EmotionBackmailService.language.value = language;
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -1600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
