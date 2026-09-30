import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/learning_controls_controller.dart';

void main() {
  testWidgets('changing timeout restarts it and never cancels pending hide', (
    tester,
  ) async {
    final controls = LearningControlsController()..enabled = true;
    addTearDown(controls.dispose);
    await tester.pump(const Duration(seconds: 4));
    controls.hideAfterSeconds = 10;
    await tester.pump(const Duration(seconds: 9));
    expect(controls.visible, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(controls.visible, isFalse);
    controls.hideAfterSeconds = 0;
    expect(controls.visible, isTrue);
    controls.pointerDown(1);
    controls.pointerUp(1);
    await tester.pump(const Duration(minutes: 1));
    expect(controls.visible, isTrue);
    controls.hideAfterSeconds = 3;
    await tester.pump(const Duration(seconds: 2));
    controls.hideAfterSeconds = 0;
    await tester.pump(const Duration(seconds: 10));
    expect(controls.visible, isTrue);
    controls.hideAfterSeconds = 3;
    await tester.pump(const Duration(seconds: 3));
    expect(controls.visible, isFalse);
  });

  testWidgets('only an active loaded practice hides after five seconds', (
    tester,
  ) async {
    final controls = LearningControlsController();
    addTearDown(controls.dispose);
    await tester.pump(const Duration(seconds: 6));
    expect(controls.visible, isTrue);
    controls.enabled = true;
    await tester.pump(const Duration(seconds: 4));
    expect(controls.visible, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(controls.visible, isFalse);
    controls.show();
    expect(controls.visible, isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(controls.visible, isFalse);
    controls.enabled = false;
    expect(controls.visible, isTrue);
    await tester.pump(const Duration(seconds: 6));
    expect(controls.visible, isTrue);
  });

  testWidgets('holding and dragging keeps controls until all fingers release', (
    tester,
  ) async {
    final controls = LearningControlsController()..enabled = true;
    addTearDown(controls.dispose);
    await tester.pump(const Duration(seconds: 4));
    controls.pointerDown(1);
    controls.pointerDown(2);
    await tester.pump(const Duration(seconds: 8));
    expect(controls.visible, isTrue);
    controls.pointerUp(1);
    await tester.pump(const Duration(seconds: 6));
    expect(controls.visible, isTrue);
    controls.pointerUp(2);
    await tester.pump(const Duration(seconds: 4));
    expect(controls.visible, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(controls.visible, isFalse);
  });

  testWidgets('disabling and returning starts a fresh timeout', (tester) async {
    final controls = LearningControlsController()..enabled = true;
    await tester.pump(const Duration(seconds: 4));
    controls.enabled = false;
    await tester.pump(const Duration(seconds: 8));
    controls.enabled = true;
    await tester.pump(const Duration(seconds: 4));
    expect(controls.visible, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(controls.visible, isFalse);
    controls.show();
    controls.dispose();
    await tester.pump(const Duration(seconds: 6));
  });
}
