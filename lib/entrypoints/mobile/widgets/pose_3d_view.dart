import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/ab_analysis/pose_3d.dart';

/// Immutable unit quaternion. Products are normalized to prevent drag drift.
final class Pose3dRotation {
  const Pose3dRotation._(this.x, this.y, this.z, this.w);
  static const identity = Pose3dRotation._(0, 0, 0, 1);
  final double x, y, z, w;

  factory Pose3dRotation._unit(double x, double y, double z, double w) {
    final n = math.sqrt(x * x + y * y + z * z + w * w);
    if (n < 1e-12) return identity;
    return Pose3dRotation._(x / n, y / n, z / n, w / n);
  }

  /// Initial presets only; interactive rotation never converts back to angles.
  factory Pose3dRotation.view({double yaw = 0, double pitch = .12}) =>
      Pose3dRotation._(-math.sin(pitch / 2), 0, 0, math.cos(pitch / 2)) *
      Pose3dRotation._(0, math.sin(yaw / 2), 0, math.cos(yaw / 2));

  Pose3dRotation operator *(Pose3dRotation b) => Pose3dRotation._unit(
    w * b.x + x * b.w + y * b.z - z * b.y,
    w * b.y - x * b.z + y * b.w + z * b.x,
    w * b.z + x * b.y - y * b.x + z * b.w,
    w * b.w - x * b.x - y * b.y - z * b.z,
  );

  (double, double, double) rotate(double vx, double vy, double vz) {
    final tx = 2 * (y * vz - z * vy),
        ty = 2 * (z * vx - x * vz),
        tz = 2 * (x * vy - y * vx);
    return (
      vx + w * tx + y * tz - z * ty,
      vy + w * ty + z * tx - x * tz,
      vz + w * tz + x * ty - y * tx,
    );
  }

  /// Screen-space arcball on the near hemisphere (negative source Z).
  static Pose3dRotation drag(Offset from, Offset to, Size size) {
    final radius = math.min(size.width, size.height) / 2;
    if (radius <= 0 || from == to) return identity;
    (double, double, double) sphere(Offset p) {
      final x = (p.dx - size.width / 2) / radius;
      final y = (size.height / 2 - p.dy) / radius;
      final r2 = x * x + y * y;
      if (r2 > 1) {
        final r = math.sqrt(r2);
        return (x / r, y / r, 0);
      }
      return (x, y, -math.sqrt(1 - r2));
    }

    final a = sphere(from), b = sphere(to);
    final dot = (a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3).clamp(-1.0, 1.0);
    if (dot < -1 + 1e-10) {
      // Opposite rim points: pick a stable axis perpendicular to the start.
      return a.$1.abs() < .9
          ? Pose3dRotation._unit(0, a.$3, -a.$2, 0)
          : Pose3dRotation._unit(-a.$3, 0, a.$1, 0);
    }
    return Pose3dRotation._unit(
      a.$2 * b.$3 - a.$3 * b.$2,
      a.$3 * b.$1 - a.$1 * b.$3,
      a.$1 * b.$2 - a.$2 * b.$1,
      1 + dot,
    );
  }
}

final class Pose3dCamera {
  Pose3dCamera({double yaw = 0, double pitch = .12, this.zoom = 1})
    : rotation = Pose3dRotation.view(yaw: yaw, pitch: pitch);
  const Pose3dCamera.oriented({required this.rotation, this.zoom = 1});
  final Pose3dRotation rotation;
  final double zoom;

  /// Input axes: X right, Y up, Z away from the source camera.
  /// Larger depth is farther from the viewer.
  (Offset, double) project(double x, double y, double z, Size size) {
    final scale = math.min(size.width / 5.4, size.height / 3.2) * zoom;
    final p = rotation.rotate(x, y, z);
    return (
      Offset(size.width / 2 + p.$1 * scale, size.height * .53 - p.$2 * scale),
      p.$3,
    );
  }
}

/// One resource owner per screen/export, with separate uniforms for A and B.
final class Pose3dRenderer {
  Pose3dRenderer._(ui.FragmentProgram program)
    : shaders = List.generate(2, (_) => program.fragmentShader());
  static Future<ui.FragmentProgram>? _program;
  static Future<Pose3dRenderer> load() async {
    try {
      return Pose3dRenderer._(
        await (_program ??= ui.FragmentProgram.fromAsset(
          'shaders/pose_3d.frag',
        )),
      );
    } catch (_) {
      _program = null;
      rethrow;
    }
  }

  final List<ui.FragmentShader> shaders;
  void dispose() {
    for (final shader in shaders) {
      shader.dispose();
    }
  }
}

/// View-space endpoints and physical radius, in metres.
typedef Pose3dCapsule = ({
  (double, double, double) a,
  (double, double, double) b,
  double radius,
});

/// Anatomical forward from the shoulder line and pelvis-to-chest axis.
/// Recompute in body space so inversion and camera rotation preserve front/back.
(double, double, double)? pose3dForward(
  Pose3dFrame frame,
  Pose3dCamera camera,
) {
  final p = frame.points;
  if (p == null || p.length != 17 || [0, 8, 11, 14].any((i) => !p[i].valid)) {
    return null;
  }
  final rx = p[14].x - p[11].x;
  final ry = p[14].y - p[11].y;
  final rz = p[14].z - p[11].z;
  final ux = p[8].x - p[0].x;
  final uy = p[8].y - p[0].y;
  final uz = p[8].z - p[0].z;
  final x = ry * uz - rz * uy;
  final y = rz * ux - rx * uz;
  final z = rx * uy - ry * ux;
  final n = math.sqrt(x * x + y * y + z * z);
  if (n < 1e-6) return null;
  return camera.rotation.rotate(x / n, y / n, z / n);
}

List<Pose3dCapsule> pose3dCapsules(Pose3dFrame frame, Pose3dCamera camera) {
  final p = frame.points;
  if (p == null || p.length != 17 || !p[0].valid) return [];
  (double, double, double) point(int i) =>
      camera.rotation.rotate(p[i].x - p[0].x, p[i].y - p[0].y, p[i].z - p[0].z);
  final result = <Pose3dCapsule>[];
  void bone(int a, int b, double radius) {
    if (p[a].valid && p[b].valid) {
      result.add((a: point(a), b: point(b), radius: radius));
    }
  }

  for (final (a, b) in pose3dBones) {
    bone(a, b, b <= 6 ? .043 : .032);
  }
  // Simplified chest and pelvis, derived solely from measured joints.
  bone(1, 4, .07);
  bone(7, 8, .105);
  for (var i = 0; i < 17; i++) {
    if (!p[i].valid) continue;
    result.add((a: point(i), b: point(i), radius: i == 10 ? .095 : .049));
  }
  final forward = pose3dForward(frame, camera);
  if (forward != null && p[10].valid) {
    final head = point(10);
    // Small nose is a visual orientation cue, not an inferred facial landmark.
    result.add((
      a: head,
      b: (
        head.$1 + forward.$1 * .13,
        head.$2 + forward.$2 * .13,
        head.$3 + forward.$3 * .13,
      ),
      radius: .027,
    ));
  }
  return result;
}

final class Pose3dPainter extends CustomPainter {
  Pose3dPainter(this.a, this.b, this.camera, {this.renderer});
  final Pose3dFrame a, b;
  final Pose3dCamera camera;
  final Pose3dRenderer? renderer;

  static Rect panel(Size size, int side) =>
      Rect.fromLTWH(side * size.width / 2, 0, size.width / 2, size.height);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xff101923), BlendMode.src);
    final scale = math.min(size.width / 5.4, size.height / 3.2) * camera.zoom;
    for (var side = 0; side < 2; side++) {
      final rect = panel(size, side);
      final center = Offset(rect.center.dx, size.height * .53);
      final color = side == 0
          ? const Color(0xff53d9ff)
          : const Color(0xffffb457);
      Offset project(double x, double y, double z) {
        final p = camera.rotation.rotate(x, y, z);
        return center + Offset(p.$1 * scale, -p.$2 * scale);
      }

      canvas.save();
      canvas.clipRect(rect.deflate(1));
      final grid = Paint()
        ..color = const Color(0xff243543)
        ..strokeWidth = 1;
      for (var i = -4; i <= 4; i++) {
        canvas.drawLine(project(i * .5, -1, -2), project(i * .5, -1, 2), grid);
        canvas.drawLine(project(-2, -1, i * .5), project(2, -1, i * .5), grid);
      }
      final frame = side == 0 ? a : b;
      final forward = pose3dForward(frame, camera);
      final capsules = pose3dCapsules(frame, camera);
      if (renderer != null) {
        final shader = renderer!.shaders[side];
        final uniforms = <double>[
          center.dx,
          center.dy,
          scale,
          color.r,
          color.g,
          color.b,
          forward?.$1 ?? 0,
          forward?.$2 ?? 0,
          forward?.$3 ?? 0,
        ];
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
        canvas.drawRect(rect, Paint()..shader = shader);
      } else {
        // Temporary loading/error fallback; still keep both subjects separated.
        capsules.sort((a, b) => (b.a.$3 + b.b.$3).compareTo(a.a.$3 + a.b.$3));
        for (final c in capsules) {
          final paint = Paint()
            ..color = forward == null
                ? color
                : Color.lerp(
                    color.withValues(
                      red: color.r * .45,
                      green: color.g * .45,
                      blue: color.b * .45,
                    ),
                    Color.lerp(color, Colors.white, .55),
                    ((1 - forward.$3) / 2).clamp(0.0, 1.0),
                  )!
            ..strokeWidth = c.radius * 2 * scale
            ..strokeCap = StrokeCap.round;
          final a = center + Offset(c.a.$1 * scale, -c.a.$2 * scale);
          final b = center + Offset(c.b.$1 * scale, -c.b.$2 * scale);
          canvas.drawLine(a, b, paint);
          canvas.drawCircle(a, c.radius * scale, paint);
        }
      }
      canvas.restore();
      final label = TextPainter(
        text: TextSpan(
          text: side == 0 ? 'A' : 'B',
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: 'Roboto',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(rect.left + 16, 12));
    }
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      Paint()
        ..color = const Color(0xff344653)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant Pose3dPainter old) =>
      old.a != a ||
      old.b != b ||
      old.camera != camera ||
      old.renderer != renderer;
}
