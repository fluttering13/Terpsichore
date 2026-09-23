import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/shared_video_playback/time_range.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/video_trim_slider.dart';

void main() {
  testWidgets('duration loss and recovery preserve the selected trim', (
    tester,
  ) async {
    final trim = TimeRange(
      start: const Duration(seconds: 2),
      end: const Duration(seconds: 10),
    );
    final duration = ValueNotifier(const Duration(seconds: 10));
    addTearDown(duration.dispose);
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<Duration>(
            valueListenable: duration,
            builder: (context, value, _) => VideoTrimSlider(
              trim: trim,
              mediaDuration: value,
              onChanged: (_) => changes++,
              onChangeEnd: (_) => changes++,
            ),
          ),
        ),
      ),
    );

    // Repeated player state updates must not leave the range outside its max,
    // including a small metadata correction and both handles past a new end.
    for (var cycle = 0; cycle < 5; cycle++) {
      for (final milliseconds in [0, -1, 9999, 1000, 10000]) {
        duration.value = Duration(milliseconds: milliseconds);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
        if (milliseconds <= 0) {
          expect(slider.values, const RangeValues(0, 0));
          expect(slider.onChanged, isNull);
          expect(slider.onChangeEnd, isNull);
          await tester.tapAt(tester.getRect(find.byType(RangeSlider)).center);
          await tester.pump();
          expect(changes, 0);
        } else {
          expect(slider.values.end, milliseconds.toDouble());
          expect(slider.values.start, milliseconds < 2000 ? 1000.0 : 2000.0);
          expect(slider.onChanged, isNotNull);
        }
      }
    }
    expect(trim.start, const Duration(seconds: 2));
    expect(trim.end, const Duration(seconds: 10));
    expect(changes, 0);
  });

  testWidgets('valid trim gestures are forwarded to the caller', (
    tester,
  ) async {
    RangeValues? changed;
    RangeValues? ended;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoTrimSlider(
            trim: TimeRange(
              start: const Duration(seconds: 2),
              end: const Duration(seconds: 8),
            ),
            mediaDuration: const Duration(seconds: 10),
            onChanged: (value) => changed = value,
            onChangeEnd: (value) => ended = value,
          ),
        ),
      ),
    );
    final finder = find.byType(RangeSlider);
    expect(
      tester.widget<RangeSlider>(finder).values,
      const RangeValues(2000, 8000),
    );
    await tester.tapAt(tester.getRect(finder).center);
    await tester.pumpAndSettle();
    expect(changed, isNotNull);
    expect(ended, changed);
    expect(tester.takeException(), isNull);
  });
}
