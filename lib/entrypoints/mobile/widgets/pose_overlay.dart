import 'package:flutter/material.dart';

import '../../../core/ab_analysis/pose_alignment.dart';

final class PoseOverlay extends StatelessWidget {
  const PoseOverlay({super.key, required this.frame});
  final PoseFrame? frame;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: PoseOverlayPainter(frame)));
}

final class PoseOverlayPainter extends CustomPainter {
  PoseOverlayPainter(this.frame);
  final PoseFrame? frame;
  static const bones = [
    (5, 6),
    (5, 7),
    (7, 9),
    (6, 8),
    (8, 10),
    (5, 11),
    (6, 12),
    (11, 12),
    (11, 13),
    (13, 15),
    (12, 14),
    (14, 16),
    (0, 1),
    (0, 2),
    (1, 3),
    (2, 4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final points = frame?.points;
    if (points == null) return;
    Offset position(int i) =>
        Offset(points[i].x * size.width, points[i].y * size.height);
    final outline = Paint()
      ..color = Colors.black87
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in bones) {
      if (points[a].score < 0.15 || points[b].score < 0.15) continue;
      canvas.drawLine(position(a), position(b), outline);
      line.color = points[a].inferred || points[b].inferred
          ? Colors.orangeAccent
          : Colors.greenAccent;
      canvas.drawLine(position(a), position(b), line);
    }
    for (var i = 0; i < points.length; i++) {
      if (points[i].score < 0.15) continue;
      canvas.drawCircle(position(i), 4, outline);
      canvas.drawCircle(
        position(i),
        2.5,
        Paint()
          ..color = points[i].inferred
              ? Colors.orangeAccent
              : Colors.yellowAccent,
      );
    }
    if (points[11].score >= 0.15 && points[12].score >= 0.15) {
      final center = (position(11) + position(12)) / 2;
      canvas.drawCircle(center, 5, Paint()..color = Colors.pinkAccent);
    }
  }

  @override
  bool shouldRepaint(PoseOverlayPainter oldDelegate) =>
      oldDelegate.frame != frame;
}
