import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/shared_video_playback/playback_rate.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/playback_rate_control.dart';

void main() {
  test('AB supports four times without changing other modes', () {
    expect(PlaybackRate.ab(4).value, 4);
    expect(PlaybackRate.ab(5).value, 4);
    expect(PlaybackRate.ab(0).value, .1);
    expect(PlaybackRate(4).value, 2);
    expect(PlaybackRate.ab(3.68 / 1.37).value, closeTo(2.686, .001));
  });

  for (final rate in [4.0, 4.1]) {
    testWidgets('AB speed dialog handles $rate', (tester) async {
      PlaybackRate? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaybackRateControl(
              value: PlaybackRate.ab(1),
              maximum: PlaybackRate.abMaximum,
              onChanged: (next) => result = next,
            ),
          ),
        ),
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.max, 4);
      expect(slider.divisions, 78);
      slider.onChanged!(4);
      expect(result!.value, 4);
      result = null;
      await tester.tap(find.text('1.00x'));
      await tester.pumpAndSettle();
      expect(find.text('可輸入 0.10 到 4.00'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '$rate');
      await tester.tap(find.text('套用'));
      await tester.pumpAndSettle();
      expect(result?.value, rate <= 4 ? rate : null);
      if (rate > 4) expect(find.byType(SnackBar), findsOneWidget);
    });
  }
}
