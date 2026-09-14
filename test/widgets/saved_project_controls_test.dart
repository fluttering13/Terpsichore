import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/shared_video_playback/playback_rate.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/playback_rate_control.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/saved_project_controls.dart';

void main() {
  testWidgets('project name dialog closes cleanly after saving', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await requestProjectName(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '測試專案');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    expect(result, '測試專案');
    expect(tester.takeException(), isNull);
  });

  testWidgets('playback rate dialog closes cleanly after applying', (
    tester,
  ) async {
    PlaybackRate? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackRateControl(
            value: PlaybackRate(1),
            showSlider: false,
            onChanged: (value) => result = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('1.00x'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1.25');
    await tester.tap(find.text('套用'));
    await tester.pumpAndSettle();

    expect(result?.value, 1.25);
    expect(tester.takeException(), isNull);
  });
}
