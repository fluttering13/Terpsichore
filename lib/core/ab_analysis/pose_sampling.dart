import 'pose_alignment.dart';

/// Decode on a 12 fps grid. Infer at 6 fps normally, 12 fps on short clips,
/// fast motion, or uncertain poses. Missing poses are never fabricated.
final class PoseSamplingPolicy {
  PoseSamplingPolicy(this.duration);
  final double duration;
  PoseFrame? _previous;
  bool _dense = false;

  bool shouldInfer(int gridIndex) =>
      duration <= 4 || _dense || gridIndex.isEven;

  void observe(PoseFrame frame) {
    var count = 0;
    var motion = 0.0;
    var paired = 0;
    for (var i = 5; i < 17; i++) {
      final p = frame.points[i];
      if (p.score < .3) continue;
      count++;
      final q = _previous?.points[i];
      if (q == null || q.score < .3) continue;
      final dt = frame.seconds - _previous!.seconds;
      if (dt <= 0) continue;
      motion +=
          ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)) / (dt * dt);
      paired++;
    }
    _dense = count < 8 || (paired >= 4 && motion / paired > .04);
    _previous = frame;
  }
}
