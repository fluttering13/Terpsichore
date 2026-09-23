import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/entrypoints/mobile/screens/ab_analysis_screen.dart';

void main() {
  for (final width in [320.0, 360.0, 390.0]) {
    testWidgets('portrait $width can switch to side-by-side without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AbAnalysisScreen())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('左右排列（橫版）'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final a = tester.getRect(find.text('A・參考影片'));
      final b = tester.getRect(find.text('B・我的影片'));
      expect(a.top, b.top);
      expect(a.left, lessThan(b.left));
      await tester.tap(find.byTooltip('上下排列（直版）'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
