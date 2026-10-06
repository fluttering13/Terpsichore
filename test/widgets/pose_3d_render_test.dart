import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/pose_3d.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/pose_3d_view.dart';

void main() {
  testWidgets('per-pixel occlusion is independent of bone submission order', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final renderer = await Pose3dRenderer.load();
      Future<Uint8List> render(
        List<Pose3dCapsule> capsules, {
        double facing = 0,
      }) async {
        final shader = renderer.shaders.first;
        final uniforms = <double>[64, 64, 40, .3, .8, 1, 0, 0, facing];
        for (var i = 0; i < 36; i++) {
          if (i < capsules.length) {
            final c = capsules[i];
            uniforms.addAll([
              c.a.$1,
              c.a.$2,
              c.a.$3,
              c.radius,
              c.b.$1,
              c.b.$2,
              c.b.$3,
              0,
            ]);
          } else {
            uniforms.addAll(List.filled(8, 0));
          }
        }
        for (var i = 0; i < uniforms.length; i++) {
          shader.setFloat(i, uniforms[i]);
        }
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 128, 128),
          Paint()..shader = shader,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(128, 128);
        final bytes = await image.toByteData();
        image.dispose();
        picture.dispose();
        return bytes!.buffer.asUint8List();
      }

      try {
        // The long diagonal's average depth is behind the horizontal bone,
        // but its crossing near the left endpoint is in front.
        const front = (a: (-.2, -.1, -.8), b: (.9, 1.0, 3.0), radius: .12);
        const back = (a: (-1.0, 0.0, 0.0), b: (1.0, 0.0, 0.0), radius: .12);
        final alone = await render([front]);
        final both = await render([front, back]);
        expect(await render([back, front]), both);
        final index = (64 * 128 + 59) * 4;
        expect(both.sublist(index, index + 4), alone.sublist(index, index + 4));
        expect(both[index + 3], 255);
        // Bone aimed straight at the camera remains a visible round surface.
        final endOn = await render([
          (a: (0.0, 0.0, -1.0), b: (0.0, 0.0, 1.0), radius: .1),
        ]);
        expect(endOn[(64 * 128 + 64) * 4 + 3], 255);
        const head = (a: (0.0, 0.0, 0.0), b: (0.0, 0.0, 0.0), radius: .2);
        final frontColor = await render([head], facing: -1);
        final backColor = await render([head], facing: 1);
        final center = (64 * 128 + 64) * 4;
        expect(frontColor[center], greaterThan(backColor[center] + 40));
        final empty = await render([]);
        expect(empty.every((v) => v == 0), isTrue);
      } finally {
        renderer.dispose();
      }
    });
  });

  testWidgets(
    'side view keeps A and B in separate panels, including export size',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await Pose3dRenderer.load();
        try {
          final points = List.generate(17, (i) => Pose3dPoint(0, i * .04, 0));
          final frame = Pose3dFrame(0, points);
          final recorder = ui.PictureRecorder();
          Pose3dPainter(
            frame,
            frame,
            Pose3dCamera(yaw: 1.57079632679, pitch: 0),
            renderer: renderer,
          ).paint(Canvas(recorder), const Size(720, 720));
          final picture = recorder.endRecording();
          final image = await picture.toImage(720, 720);
          final bytes = (await image.toByteData())!.buffer.asUint8List();
          image.dispose();
          picture.dispose();
          int channel(int x, int y, int c) => bytes[(y * 720 + x) * 4 + c];
          expect(channel(180, 365, 2), greaterThan(channel(180, 365, 0)));
          expect(channel(540, 365, 0), greaterThan(channel(540, 365, 2)));
          expect(channel(360, 365, 0), lessThan(100));
        } finally {
          renderer.dispose();
        }
      });
    },
  );
}
