import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/video_conversion/video_conversion.dart';
import 'package:terpsichore/entrypoints/mobile/screens/video_conversion_screen.dart';

void main() {
  for (final width in [320.0, 360.0, 390.0]) {
    testWidgets('conversion dropdowns fit $width with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 850),
              textScaler: TextScaler.linear(1.3),
            ),
            child: const Scaffold(body: VideoConversionScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final quality = find.byType(DropdownButtonFormField<VideoQuality>);
      await tester.scrollUntilVisible(quality, 200);
      await tester.pumpAndSettle();
      await tester.tap(quality);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
