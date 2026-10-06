import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/pose_3d.dart';
import 'package:terpsichore/entrypoints/mobile/widgets/pose_3d_view.dart';

void main() {
  const size = Size(720, 720);

  test(
    'front direction follows the body through inversion and camera rotation',
    () {
      final points = List.filled(17, const Pose3dPoint(0, 0, 0));
      points[8] = const Pose3dPoint(0, .5, 0);
      points[10] = const Pose3dPoint(0, .8, 0);
      points[11] = const Pose3dPoint(.2, .5, 0);
      points[14] = const Pose3dPoint(-.2, .5, 0);
      final frame = Pose3dFrame(0, points);
      final camera = Pose3dCamera(pitch: 0);
      expect(pose3dForward(frame, camera)!.$3, closeTo(-1, 1e-9));
      expect(
        pose3dForward(frame, Pose3dCamera(yaw: math.pi, pitch: 0))!.$3,
        closeTo(1, 1e-9),
      );
      final inverted = Pose3dFrame(0, [
        for (final p in points) Pose3dPoint(-p.x, -p.y, p.z),
      ]);
      expect(pose3dForward(inverted, camera)!.$3, closeTo(-1, 1e-9));
      expect(pose3dCapsules(frame, camera).length, 36);
      expect(pose3dCapsules(frame, camera).last.b.$3, closeTo(-.13, 1e-9));
    },
  );

  test('capsule geometry rejects missing and invalid roots and joints', () {
    final camera = Pose3dCamera();
    expect(pose3dCapsules(const Pose3dFrame(0, null), camera), isEmpty);
    expect(pose3dCapsules(const Pose3dFrame(0, []), camera), isEmpty);
    final points = List.generate(17, (i) => Pose3dPoint(i * .1, 0, 2));
    final full = pose3dCapsules(Pose3dFrame(0, points), camera);
    expect(full.length, 35); // Fits the shader's 36 slots.
    points[3] = const Pose3dPoint(double.nan, 0, 0);
    final partial = pose3dCapsules(Pose3dFrame(0, points), camera);
    expect(partial.length, 33); // Ankle sphere and its incident bone omitted.
    expect(
      partial.every(
        (c) => [
          c.a.$1,
          c.a.$2,
          c.a.$3,
          c.b.$1,
          c.b.$2,
          c.b.$3,
        ].every((v) => v.isFinite),
      ),
      isTrue,
    );
    points[0] = const Pose3dPoint(0, 0, 0, .1);
    expect(pose3dCapsules(Pose3dFrame(0, points), camera), isEmpty);
  });

  test(
    'arcball follows the pointer and reverses without changing geometry',
    () {
      const from = Offset(360, 360), to = Offset(540, 360);
      final turn = Pose3dRotation.drag(from, to, size);
      final p = turn.rotate(0, 0, -1);
      expect(p.$1, closeTo(.5, 1e-10));
      expect(p.$3, closeTo(-math.sqrt(.75), 1e-10));
      final back = (Pose3dRotation.drag(to, from, size) * turn).rotate(1, 2, 3);
      expect(back.$1, closeTo(1, 1e-10));
      expect(back.$2, closeTo(2, 1e-10));
      expect(back.$3, closeTo(3, 1e-10));
    },
  );

  test('rotation remains controllable at and beyond the overhead pole', () {
    final drag = Pose3dRotation.drag(
      const Offset(360, 360),
      const Offset(460, 400),
      size,
    );
    for (final pitch in [
      math.pi / 2 - 1e-6,
      math.pi / 2,
      math.pi / 2 + 1e-6,
      math.pi,
    ]) {
      final initial = Pose3dRotation.view(pitch: pitch);
      final a = initial.rotate(0, 1, 0);
      final b = (drag * initial).rotate(0, 1, 0);
      expect(
        (a.$1 - b.$1).abs() + (a.$2 - b.$2).abs() + (a.$3 - b.$3).abs(),
        greaterThan(.1),
      );
      expect(b.$1 * b.$1 + b.$2 * b.$2 + b.$3 * b.$3, closeTo(1, 1e-10));
    }
  });

  test('opposite arcball rim and zero movement stay finite', () {
    final opposite = Pose3dRotation.drag(
      const Offset(0, 360),
      const Offset(720, 360),
      size,
    );
    expect(opposite.rotate(-1, 0, 0).$1, closeTo(1, 1e-10));
    expect(
      Pose3dRotation.drag(Offset.zero, Offset.zero, Size.zero).rotate(1, 2, 3),
      (1.0, 2.0, 3.0),
    );
  });

  test('many drag compositions preserve lengths and orthogonal axes', () {
    var rotation = Pose3dRotation.view();
    for (var i = 0; i < 10000; i++) {
      rotation =
          Pose3dRotation.drag(
            Offset(360 + 200 * math.cos(i * .1), 360 + 200 * math.sin(i * .1)),
            Offset(
              360 + 200 * math.cos((i + 1) * .1),
              360 + 200 * math.sin((i + 1) * .1),
            ),
            size,
          ) *
          rotation;
    }
    final x = rotation.rotate(1, 0, 0), y = rotation.rotate(0, 1, 0);
    expect(x.$1 * x.$1 + x.$2 * x.$2 + x.$3 * x.$3, closeTo(1, 1e-10));
    expect(x.$1 * y.$1 + x.$2 * y.$2 + x.$3 * y.$3, closeTo(0, 1e-10));
  });

  test('front view preserves source image axes and far-to-near depth', () {
    final camera = Pose3dCamera(pitch: 0);
    final origin = camera.project(0, 0, 0, size);
    expect(camera.project(1, 0, 0, size).$1.dx, greaterThan(origin.$1.dx));
    expect(camera.project(0, 1, 0, size).$1.dy, lessThan(origin.$1.dy));
    expect(camera.project(0, 0, 1, size).$2, greaterThan(origin.$2));
  });

  test('overhead view puts far floor above near floor and head nearer', () {
    final camera = Pose3dCamera(pitch: math.pi / 2);
    final near = camera.project(0, -1, -1, size);
    final far = camera.project(0, -1, 1, size);
    expect(far.$1.dy, lessThan(near.$1.dy));
    expect(
      camera.project(0, 1, 0, size).$2,
      lessThan(camera.project(0, -1, 0, size).$2),
    );
  });

  test('clockwise floor motion stays clockwise from above at every yaw', () {
    for (final yaw in [0.0, .7, math.pi, -math.pi / 2]) {
      final camera = Pose3dCamera(yaw: yaw, pitch: 1.4);
      // Far -> right -> near -> left: clockwise as seen from above.
      final points = [
        camera.project(0, 0, 1, size).$1,
        camera.project(1, 0, 0, size).$1,
        camera.project(0, 0, -1, size).$1,
        camera.project(-1, 0, 0, size).$1,
      ];
      var area = 0.0;
      for (var i = 0; i < points.length; i++) {
        final a = points[i], b = points[(i + 1) % points.length];
        area += a.dx * b.dy - b.dx * a.dy;
      }
      // Screen Y grows downwards, so clockwise polygons have positive area.
      expect(area, greaterThan(0), reason: 'Reversed at yaw $yaw');
    }
  });
}
