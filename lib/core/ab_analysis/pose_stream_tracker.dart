import 'pose_alignment.dart';
import 'thunder_crop_tracking.dart';
import 'rtmpose_processing.dart';

/// STREAM-like ROI reuse, not a reimplementation of ML Kit's private tracker.
/// A lost track resets the NEXT input to full-frame; never reruns this sample.
final class PoseStreamTracker {
  PoseStreamTracker(this.aspectRatio);
  final double aspectRatio;
  PersonBox _crop = thunderFullFrame;
  PoseFrame? _previous;

  PersonBox cropFor(double seconds) {
    if (_previous != null &&
        (seconds <= _previous!.seconds || seconds - _previous!.seconds > .3)) {
      reset();
    }
    return _crop;
  }

  bool observe(PoseFrame pose) {
    if (pose.points.length != 17 ||
        pose.points.any(
          (p) => !p.x.isFinite || !p.y.isFinite || !p.score.isFinite,
        ) ||
        ![5, 6].any((j) => pose.points[j].score >= .2) ||
        ![11, 12].any((j) => pose.points[j].score >= .2) ||
        pose.points.skip(5).where((p) => p.score >= .2).length < 6 ||
        !thunderSameSubject(pose, _previous, aspectRatio)) {
      reset();
      return false;
    }
    _previous = pose;
    _crop = thunderNextCrop(pose, aspectRatio);
    return true;
  }

  void reset() {
    _previous = null;
    _crop = thunderFullFrame;
  }
}
