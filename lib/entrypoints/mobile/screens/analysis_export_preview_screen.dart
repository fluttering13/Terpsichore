import '../localization/app_text.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/ab_analysis/analysis_project.dart';

/// Borrows the editor's players; playback, audio and ownership stay in the editor.
class AnalysisExportPreviewScreen extends StatefulWidget {
  const AnalysisExportPreviewScreen({
    super.key,
    required this.project,
    required this.playerA,
    required this.playerB,
    required this.onToggle,
    required this.onSeekStart,
    required this.onSeek,
  });

  final AnalysisProject project;
  final VideoPlayerController playerA;
  final VideoPlayerController playerB;
  final Future<void> Function() onToggle;
  final Future<void> Function(double) onSeekStart;
  final Future<void> Function(double) onSeek;

  @override
  State<AnalysisExportPreviewScreen> createState() => _PreviewState();
}

class _PreviewState extends State<AnalysisExportPreviewScreen> {
  bool _busy = false;
  double? _dragProgress;
  Future<void>? _pause;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appText(context, "無法播放預覽：{0}", [appError(context, error)]),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _video(VideoPlayerController player) => Center(
    child: AspectRatio(
      aspectRatio: player.value.aspectRatio,
      child: VideoPlayer(player),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && _dragProgress == null,
    child: Scaffold(
      appBar: AppBar(title: Text(appText(context, "合成預覽"))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.playerA, widget.playerB]),
          builder: (context, _) {
            final sideBySide =
                widget.project.output == AnalysisOutput.sideBySide;
            final clock = sideBySide ? widget.playerA : widget.playerB;
            final track = sideBySide
                ? widget.project.trackA
                : widget.project.trackB;
            final duration = sideBySide
                ? widget.project.sharedTimelineDuration
                : widget.project.trackB.effectiveDuration;
            final progress = duration.inMicroseconds == 0
                ? 0.0
                : ((clock.value.position - track.trim.start).inMicroseconds /
                          track.rate.value /
                          duration.inMicroseconds)
                      .clamp(0.0, 1.0);
            final hasError =
                widget.playerA.value.hasError || widget.playerB.value.hasError;
            final controlsDisabled = _busy || _dragProgress != null;
            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: sideBySide
                          ? 16 / 9
                          : widget.playerB.value.aspectRatio,
                      child: ColoredBox(
                        color: Colors.black,
                        child: sideBySide
                            ? Row(
                                children: [
                                  Expanded(child: _video(widget.playerA)),
                                  Expanded(child: _video(widget.playerB)),
                                ],
                              )
                            : _video(widget.playerB),
                      ),
                    ),
                  ),
                ),
                if (hasError) Text(appText(context, "預覽播放失敗，請回到上一步重試。")),
                Slider(
                  value: _dragProgress ?? progress,
                  onChangeStart: _busy || hasError
                      ? null
                      : (value) {
                          setState(() => _dragProgress = value);
                          _pause = widget.onSeekStart(value);
                          // Attach a handler immediately; the commit reports errors.
                          _pause!.ignore();
                        },
                  onChanged: _busy || hasError
                      ? null
                      : (value) => setState(() => _dragProgress = value),
                  onChangeEnd: _busy || hasError
                      ? null
                      : (value) async {
                          await _run(() async {
                            await _pause;
                            await widget.onSeek(value);
                          });
                          if (mounted) setState(() => _dragProgress = null);
                        },
                ),
                IconButton(
                  tooltip: clock.value.isPlaying
                      ? appText(context, "暫停")
                      : appText(context, "播放預覽"),
                  onPressed: controlsDisabled || hasError
                      ? null
                      : () => _run(widget.onToggle),
                  icon: Icon(
                    clock.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(appText(context, "直接預覽目前的裁切、倍速與音訊設定，確認後才合成輸出。")),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: controlsDisabled
                              ? null
                              : () => Navigator.pop(context, false),
                          child: Text(appText(context, "回到上一步")),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: controlsDisabled || hasError
                              ? null
                              : () => Navigator.pop(context, true),
                          child: Text(appText(context, "確認輸出")),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
