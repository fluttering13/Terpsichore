import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/shared_video_playback/time_range.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/video_trim_slider.dart';

void main() {
  for (final boundary in [0, 10000]) {
    testWidgets('collapsed trim at $boundary can be dragged open', (
      tester,
    ) async {
      var trim = TimeRange(
        start: Duration(milliseconds: boundary),
        end: Duration(milliseconds: boundary),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => VideoTrimSlider(
                trim: trim,
                mediaDuration: const Duration(seconds: 10),
                onChanged: (values) => setState(() {
                  trim = TimeRange(
                    start: Duration(milliseconds: values.start.round()),
                    end: Duration(milliseconds: values.end.round()),
                  );
                }),
                onChangeEnd: (_) {},
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(RangeSlider));
      final from = Offset(
        boundary == 0 ? rect.left + 24 : rect.right - 24,
        rect.center.dy,
      );
      await tester.dragFrom(from, Offset(boundary == 0 ? 150 : -150, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(trim.duration.inMilliseconds, greaterThan(100));
      expect(
        boundary == 0 ? trim.start.inMilliseconds : trim.end.inMilliseconds,
        boundary,
      );
    });
  }

  testWidgets('end cannot collapse onto start and short clips remain valid', (
    tester,
  ) async {
    for (final length in [50, 10000]) {
      RangeValues? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoTrimSlider(
              trim: TimeRange(
                start: Duration.zero,
                end: Duration(milliseconds: length),
              ),
              mediaDuration: Duration(milliseconds: length),
              onChanged: (values) => changed = values,
              onChangeEnd: (_) {},
            ),
          ),
        ),
      );
      final slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
      slider.onChanged!(const RangeValues(0, 0));
      expect(changed, RangeValues(0, length < 100 ? length.toDouble() : 100));
      expect(tester.takeException(), isNull);
    }
  });

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
          expect(slider.values.start, milliseconds < 2000 ? 900.0 : 2000.0);
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
