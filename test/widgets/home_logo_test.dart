import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/entrypoints/mobile/screens/home_screen.dart';
import 'package:terpsichore/infrastructure/engagement/emotion_backmail_service.dart';

void main() {
  testWidgets('home logo follows the 100-day consecutive login threshold', (
    tester,
  ) async {
    final previous = EmotionBackmailService.onlineStreak.value;
    addTearDown(() => EmotionBackmailService.onlineStreak.value = previous);
    EmotionBackmailService.onlineStreak.value = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HomeScreen(onOpenFeature: (_) {})),
      ),
    );

    String logo() =>
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName;
    expect(logo(), 'asset/logo.png');
    for (final days in [99, 100, 101, 1]) {
      EmotionBackmailService.onlineStreak.value = days;
      await tester.pump();
      expect(logo(), days >= 100 ? 'asset/logo2.png' : 'asset/logo.png');
    }
  });
}
