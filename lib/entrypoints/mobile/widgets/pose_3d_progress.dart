import 'package:flutter/material.dart';
import '../../../infrastructure/analysis/pose_3d_job.dart';
import '../localization/app_text.dart';

/// Used for both the first run and a rerun over the retained result.
class Pose3dProgress extends StatelessWidget {
  const Pose3dProgress({super.key, required this.job});
  final Pose3dJob job;

  String _remaining(BuildContext context) {
    if (job.progress >= 1) return appText(context, '正在整理結果…');
    final remaining = job.estimatedRemaining;
    if (remaining == null) return appText(context, '預估剩餘時間：估算中…');
    final seconds = (remaining.inMicroseconds / 1e6).ceil();
    final duration = seconds >= 3600
        ? appText(context, '{0} 小時 {1} 分', [
            seconds ~/ 3600,
            (seconds % 3600) ~/ 60,
          ])
        : seconds >= 60
        ? appText(context, '{0} 分 {1} 秒', [seconds ~/ 60, seconds % 60])
        : appText(context, '{0} 秒', [seconds]);
    return appText(context, '預估剩餘時間：約 {0}', [duration]);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          appText(context, '正在分析 {0}：{1}%', [
            job.side,
            (job.progress * 100).round(),
          ]),
          textAlign: TextAlign.center,
        ),
        if (job.status == Pose3dJobStatus.running)
          Text(
            _remaining(context),
            key: const ValueKey('pose3d-remaining'),
            textAlign: TextAlign.center,
          ),
      ],
    ),
  );
}
