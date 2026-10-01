import '../localization/app_text.dart';
import 'package:terpsichore/infrastructure/engagement/easter_egg_service.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/ab_analysis/analysis_exporter.dart';
import '../../../core/ab_analysis/analysis_gallery.dart';
import '../../../core/ab_analysis/analysis_project.dart';
import '../../../core/ab_analysis/pose_3d.dart';
import 'pose_3d_screen.dart';
import '../../../infrastructure/analysis/pose_3d_job.dart';
import '../../../core/ab_analysis/pose_alignment.dart';
import '../../../core/ab_analysis/parallel_pose_jobs.dart';
import '../../../core/ab_analysis/pose_post_processing.dart';
import '../../../core/saved_projects/saved_project.dart';
import '../../../core/shared_video_playback/playback_rate.dart';
import '../../../core/shared_video_playback/time_range.dart';
import '../../../core/shared_video_playback/video_source.dart';
import '../../../infrastructure/analysis/ffmpeg_analysis_exporter.dart';
import '../../../infrastructure/analysis/device_analysis_gallery.dart';
import '../../../infrastructure/analysis/local_analysis_audio_picker.dart';
import '../../../infrastructure/analysis/movenet_analyzer.dart';
import '../../../infrastructure/media/local_video_picker.dart';
import '../../../infrastructure/media/same_video.dart';
import '../../../infrastructure/saved_projects/local_saved_project_store.dart';
import '../../../infrastructure/saved_projects/project_media_store.dart';
import '../../../infrastructure/video_playback/latest_video_seeker.dart';
import '../../../infrastructure/video_playback/local_video_controller.dart';
import '../../../infrastructure/video_playback/video_playback_ready.dart';
import 'analysis_export_preview_screen.dart';
import '../widgets/playback_rate_control.dart';
import '../widgets/precision_scrub_slider.dart';
import '../widgets/saved_project_controls.dart';
import '../widgets/time_text.dart';
import '../widgets/video_trim_slider.dart';
import '../widgets/pose_overlay.dart';

final class AbAnalysisScreen extends StatefulWidget {
  const AbAnalysisScreen({super.key});

  @override
  State<AbAnalysisScreen> createState() => _AbAnalysisScreenState();
}

enum _ComparisonLayout { vertical, horizontal }

enum _BAlignmentMode {
  automatic('時間軸與倍速都搜尋', '搜尋 B 整部影片的起點與倍速（0.1–4x），終點設為影片結尾。'),
  fixedTimeline('固定時間軸，只搜尋倍速', '保留 B 目前的裁切起點與終點，只搜尋倍速（0.1–4x）。'),
  fixedRate('固定倍速，只搜尋時間軸', '保留 B 目前的倍速，搜尋整部影片的起點，終點設為影片結尾。');

  const _BAlignmentMode(this.label, this.description);
  final String label;
  final String description;
}

final class _TrackState {
  _TrackState({
    required this.source,
    required this.player,
    required this.seeker,
    required this.trim,
    required this.rate,
  });

  final VideoSource source;
  final VideoPlayerController player;
  final LatestVideoSeeker seeker;
  TimeRange trim;
  PlaybackRate rate;
  PoseSequence? pose;
  PoseSequence? processedPose;
  bool useProcessedPose = true;
  double? poseStart;
  double? poseEnd;
  bool showPose = false;

  AnalysisTrack toDomain() => AnalysisTrack(
    source: source,
    mediaDuration: player.value.duration,
    trim: trim,
    rate: rate,
  );
}

final class _AbAnalysisScreenState extends State<AbAnalysisScreen> {
  static const _picker = LocalVideoPicker();
  static const _audioPicker = LocalAnalysisAudioPicker();
  static const _exporter = FfmpegAnalysisExporter();
  static const _gallery = DeviceAnalysisGallery();
  static final _projectStore = LocalSavedProjectStore.instance;
  static const _projectMediaStore = ProjectMediaStore();

  _TrackState? _trackA;
  _TrackState? _trackB;
  final AudioPlayer _customAudioPlayer = AudioPlayer();
  Timer? _customAudioStartTimer;
  Timer? _customAudioEndTimer;
  AnalysisCustomAudio? _customAudio;
  double _progress = 0;
  bool _commonPlaying = false;
  bool _startingCommonPlayback = false;
  bool _endingCommonPlayback = false;
  bool _orientationLocked = false;
  bool _exporting = false;
  bool _openingPose3d = false;
  bool _previewing = false;

  bool get _previewBOnly => _previewing && _output == AnalysisOutput.trackBOnly;
  bool _mirrorA = false;
  bool _mirrorB = false;
  _ComparisonLayout _layout = _ComparisonLayout.vertical;
  AnalysisOutput _output = AnalysisOutput.sideBySide;
  AnalysisAudioSource _audioSource = AnalysisAudioSource.trackB;
  AnalysisGalleryFolder _exportFolder = AnalysisGalleryFolder.defaultFolder;
  String? _savedProjectId;
  String? _savedProjectName;
  MoveNetAnalyzer? _poseAnalyzer;
  final List<MoveNetAnalyzer> _activePoseAnalyzers = [];
  void _cancelPoseAnalysis() {
    for (final analyzer in _activePoseAnalyzers) {
      analyzer.cancelled = true;
    }
  }

  _BAlignmentMode _bAlignmentMode = _BAlignmentMode.automatic;
  double _smoothWindow = .5;
  int _samplingFps = 0; // 0 preserves adaptive 6–12 FPS.
  static const _fpsOptions = [0, 1, 2, 3, 4, 5, 6, 8, 12, 15, 24, 30];
  bool _settingsReady = false;
  Pose3dSettings _pose3dSettings = const Pose3dSettings();
  TimeRange? _beforeAiTrim;
  PlaybackRate? _beforeAiRate;
  _TrackState? _beforeAiTrack;
  String? _alignmentLabel;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAiSettings());
  }

  Future<File> _aiSettingsFile() async => File(
    '${(await getApplicationSupportDirectory()).path}/pose_settings.json',
  );

  Future<void> _loadAiSettings() async {
    try {
      final file = await _aiSettingsFile();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map;
        _bAlignmentMode = _BAlignmentMode.values.firstWhere(
          (mode) => mode.name == data['bAlignmentMode'],
          orElse: () => _BAlignmentMode.automatic,
        );
        final window = data['smoothWindow'];
        final fps = data['samplingFps'];
        _pose3dSettings = Pose3dSettings.fromJson(data['pose3d']);
        // Ignore the retired multiPersonFiltering preference: tracking is always on.
        if (fps is int && _fpsOptions.contains(fps)) _samplingFps = fps;
        if (window is num && window.isFinite && window >= 0) {
          _smoothWindow = window.toDouble();
        }
      }
    } catch (_) {
      /* Invalid preferences fall back to the documented default. */
    }
    if (mounted) {
      setState(() {
        _settingsReady = true;
      });
    }
  }

  Future<void> _showAiSettings() async {
    var mode = _bAlignmentMode;
    double? window = _smoothWindow;
    var fps = _samplingFps;
    var model3d = _pose3dSettings.model;
    var fps3d = _pose3dSettings.fps;
    var interpolate3d = _pose3dSettings.interpolate;
    final value = await showDialog<(_BAlignmentMode, double, int, Pose3dSettings)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(appText(context, "AI 設定")),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  appText(context, 'AI 對齊設定'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                appText(
                  context,
                  "自動追蹤主要人物，每個採樣影格只推論一次。遮擋或多人交錯時仍可能追錯，請用骨架預覽確認。",
                ),
              ),
              DropdownButtonFormField<int>(
                key: const ValueKey('pose-sampling-fps'),
                isExpanded: true,
                itemHeight: null,
                initialValue: fps,
                decoration: InputDecoration(
                  labelText: appText(context, "骨架採樣 FPS"),
                ),
                items: _fpsOptions
                    .map(
                      (n) => DropdownMenuItem(
                        value: n,
                        child: Text(
                          n == 0 ? appText(context, "自動（6–12 FPS）") : '$n FPS',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (n) {
                  if (n != null) update(() => fps = n);
                },
              ),
              Text(
                appText(
                  context,
                  "固定 FPS 越低分析越快，但可能漏掉快速動作。只影響 AI 採樣，不改變影片播放或輸出 FPS。修改後需重新分析。",
                ),
              ),
              TextFormField(
                initialValue: _smoothWindow.toString(),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: appText(context, "骨架平滑窗口（秒）"),
                  helperText: appText(
                    context,
                    "建議從 0.5 秒開始，可輸入任意非負秒數，前後各半。越高越能減少抖動，但可能抹平快速動作；越低越保留動作細節，也較容易抖動。0 秒停用平滑。採樣 FPS 較低時，小窗口可能沒有足夠影格可平滑。",
                  ),
                  helperMaxLines: 6,
                  errorText: window == null
                      ? appText(context, "請輸入大於或等於 0 的有效秒數")
                      : null,
                ),
                onChanged: (text) => update(() {
                  final n = double.tryParse(text.replaceAll(',', '.'));
                  window = n != null && n.isFinite && n >= 0 ? n : null;
                }),
              ),
              DropdownButtonFormField<_BAlignmentMode>(
                initialValue: mode,
                isExpanded: true,
                itemHeight: null,
                decoration: InputDecoration(
                  labelText: appText(context, "B 對齊模式（A 始終固定）"),
                ),
                items: _BAlignmentMode.values
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(appText(context, m.label)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) update(() => mode = v);
                },
              ),
              Text(
                appText(context, "A 的裁切與倍速始終保持不變。{0}允許尾端不同時播完。", [
                  appText(context, mode.description),
                ]),
              ),
              const Divider(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  appText(context, '3D Pose 設定'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              DropdownButtonFormField<Pose3dModel>(
                key: const ValueKey('pose3d-model'),
                isExpanded: true,
                itemHeight: null,
                initialValue: model3d,
                decoration: InputDecoration(
                  labelText: appText(context, '3D 模型'),
                ),
                items: Pose3dModel.values
                    .map(
                      (m) => DropdownMenuItem(value: m, child: Text(m.label)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) update(() => model3d = v);
                },
              ),
              DropdownButtonFormField<int>(
                key: const ValueKey('pose3d-fps'),
                isExpanded: true,
                itemHeight: null,
                initialValue: fps3d,
                decoration: InputDecoration(
                  labelText: appText(context, '3D 推論 FPS'),
                ),
                items: Pose3dSettings.fpsOptions
                    .map(
                      (n) => DropdownMenuItem(value: n, child: Text('$n FPS')),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) update(() => fps3d = v);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(appText(context, 'Post-processing：內插其餘影格')),
                subtitle: Text(
                  appText(context, '內插播放與輸出影格；短暫漏偵測最多補 2 個採樣點，前後間隔須在 0.6 秒內。'),
                ),
                value: interpolate3d,
                onChanged: (v) => update(() => interpolate3d = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(appText(context, "取消")),
            ),
            FilledButton(
              onPressed: window == null
                  ? null
                  : () => Navigator.pop(context, (
                      mode,
                      window!,
                      fps,
                      Pose3dSettings(
                        model: model3d,
                        fps: fps3d,
                        interpolate: interpolate3d,
                      ),
                    )),
              child: Text(appText(context, "儲存")),
            ),
          ],
        ),
      ),
    );
    if (value == null || !mounted) return;
    try {
      final file = await _aiSettingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'bAlignmentMode': value.$1.name,
          'smoothWindow': value.$2,
          'samplingFps': value.$3,
          'pose3d': value.$4.toJson(),
        }),
        flush: true,
      );
      if (mounted) {
        setState(() {
          final fpsChanged = _samplingFps != value.$3;
          _samplingFps = value.$3;
          _pose3dSettings = value.$4;
          _bAlignmentMode = value.$1;
          _smoothWindow = value.$2;
          for (final track in [_trackA, _trackB]) {
            if (track == null) continue;
            if (fpsChanged) {
              track.pose = null;
              track.processedPose = null;
              track.poseStart = null;
              track.poseEnd = null;
            }
            track.useProcessedPose = _smoothWindow > 0;
            if (track.pose != null) {
              track.processedPose = medianPoseSequence(
                track.pose!,
                _smoothWindow,
              );
            }
          }
        });
      }
    } catch (error) {
      if (mounted) {
        _showProjectMessage(
          appText(context, "設定儲存失敗：{0}", [appError(context, error)]),
        );
      }
    }
  }

  Future<void> _openPose3d() async {
    final a = _trackA, b = _trackB;
    if (a == null ||
        b == null ||
        _poseAnalyzer != null ||
        _exporting ||
        _openingPose3d) {
      return;
    }
    final project = AnalysisProject(
      trackA: a.toDomain(),
      trackB: b.toDomain(),
      output: AnalysisOutput.sideBySide,
    );
    if (project.sharedTimelineDuration <= Duration.zero) return;
    setState(() => _openingPose3d = true);
    try {
      _cancelCustomAudioSchedule();
      await Future.wait([
        a.player.pause(),
        b.player.pause(),
        _customAudioPlayer.pause(),
      ]);
      if (!mounted) return;
      setState(() => _commonPlaying = false);
      if (_savedProjectId != null &&
          Pose3dJobs.instance.current?.busy != true) {
        if (!await _saveProject(showMessage: false)) return;
      }
      final job = await Pose3dJobs.instance.getOrStart(
        project,
        _pose3dSettings,
        savedProjectId: _savedProjectId,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Pose3dScreen(job: job, folder: _exportFolder),
        ),
      );
      await _loadAiSettings();
    } finally {
      if (mounted) setState(() => _openingPose3d = false);
    }
  }

  Future<void> _togglePose(bool isA) async {
    final track = isA ? _trackA : _trackB;
    if (track == null) return;
    if (_poseAnalyzer != null) {
      _showProjectMessage(appText(context, "請等 AI 對齊分析完成後再顯示骨架。"));
      return;
    }
    final sequence = track.useProcessedPose ? track.processedPose : track.pose;
    if (!track.showPose &&
        !(sequence?.frames.any(
              (frame) => PoseOverlayPainter.bones.any(
                (bone) =>
                    frame.points.length > bone.$2 &&
                    frame.points[bone.$1].score >= 0.15 &&
                    frame.points[bone.$2].score >= 0.15,
              ),
            ) ??
            false)) {
      _showProjectMessage(
        track.pose == null
            ? appText(context, "請按「AI 對齊」一次分析 A、B。")
            : appText(context, "目前沒有可顯示的骨架，請調整片段後重新分析。"),
      );
      return;
    }
    setState(() => track.showPose = !track.showPose);
    EasterEggService.instance.count('hades', 11);
    if (track.showPose) {
      EasterEggService.instance.engine.trigger('bones', oncePerDay: true);
    }
  }

  Future<void> _runPoseAnalysis() async {
    if (_poseAnalyzer != null || _exporting || !_settingsReady) return;
    final mode = _bAlignmentMode;
    final lockTimeline = mode == _BAlignmentMode.fixedTimeline;
    final lockRate = mode == _BAlignmentMode.fixedRate;
    final a = _trackA;
    final b = _trackB;
    if (a == null || b == null) return;
    final tracks = [a, b];
    final originalTrim = b.trim;
    final originalRate = b.rate;
    final searchStart = lockTimeline
        ? originalTrim.start.inMicroseconds / 1e6
        : 0.0;
    final anchorEnd =
        (lockTimeline ? originalTrim.end : b.player.value.duration)
            .inMicroseconds /
        1e6;
    final searchEnd = anchorEnd;
    if (a.trim.duration <= Duration.zero || searchEnd <= searchStart) {
      _showProjectMessage(appText(context, "請選擇有效的 A、B 分析區間。"));
      return;
    }
    final analyzer = MoveNetAnalyzer.forApp(
      isAndroid: Platform.isAndroid,
      trackMainPerson: true,
    );
    final analyzerB = MoveNetAnalyzer.forApp(
      isAndroid: Platform.isAndroid,
      trackMainPerson: true,
    );
    _activePoseAnalyzers.addAll([analyzer, analyzerB]);
    _poseAnalyzer = analyzer;
    try {
      await _beginCommonSeek(0);
    } catch (error) {
      _poseAnalyzer = null;
      _activePoseAnalyzers.clear();
      if (mounted) {
        _showProjectMessage(
          appText(context, "無法暫停播放：{0}", [appError(context, error)]),
        );
      }
      return;
    }
    if (!mounted) {
      _poseAnalyzer = null;
      _activePoseAnalyzers.clear();
      return;
    }
    final status = ValueNotifier<String>(
      appText(context, "{0} 分析準備中\n追蹤主要人物；多人交錯時請檢查主角", [
        Platform.isAndroid ? 'ML Kit Accurate' : 'Thunder INT8',
      ]),
    );
    final dialog = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(
            appText(context, "AI 對齊 · {0}", [appText(context, mode.label)]),
          ),
          content: ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (_, value, child) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
                Text(value),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _cancelPoseAnalysis();
                status.value = appText(context, "正在取消，完成目前工作後釋放模型…");
              },
              child: Text(appText(context, "取消")),
            ),
          ],
        ),
      ),
    );
    final navigator = Navigator.of(context);
    unawaited(navigator.push(dialog));
    PoseAlignmentResult? result;
    Object? failure;
    try {
      final progress = [0.0, 0.0];
      Future<void> analyzeTrack(int index) async {
        final track = tracks[index];
        final trackAnalyzer = index == 0 ? analyzer : analyzerB;
        try {
          final start = identical(track, b)
              ? searchStart
              : track.trim.start.inMicroseconds / 1e6;
          final end = identical(track, b)
              ? searchEnd
              : track.trim.end.inMicroseconds / 1e6;
          if (track.pose == null ||
              track.poseStart! > start ||
              track.poseEnd! < end) {
            final sequence = await trackAnalyzer.analyze(
              path: track.source.path,
              start: start,
              end: end,
              aspectRatio: track.player.value.aspectRatio,
              samplingFps: _samplingFps == 0 ? null : _samplingFps,
              onProgress: (p) {
                if (!analyzer.cancelled) {
                  progress[index] = p;
                  status.value =
                      appText(context, "{0} 並行分析\nA {1}% · B {2}%\n追蹤主要人物", [
                        Platform.isAndroid ? 'ML Kit Accurate' : 'Thunder INT8',
                        (progress[0] * 100).round(),
                        (progress[1] * 100).round(),
                      ]);
                }
              },
            );
            if (!mounted || analyzer.cancelled) throw PoseAnalysisCancelled();
            track.pose = sequence;
            track.processedPose = medianPoseSequence(sequence, _smoothWindow);
            track.useProcessedPose = _smoothWindow > 0;
            track.poseStart = start;
            track.poseEnd = end;
          }
          if (!mounted || analyzer.cancelled) throw PoseAnalysisCancelled();
          progress[index] = 1;
        } catch (error) {
          if (error is! PoseAnalysisCancelled) failure ??= error;
          _cancelPoseAnalysis();
          rethrow;
        }
      }

      // Wait for both jobs (including cleanup on failure) before using results
      // or disposing the shared progress notifier.
      await runParallelPoseJobs(() => analyzeTrack(0), () => analyzeTrack(1));
      {
        if (mounted) {
          status.value = appText(context, "B：{0}…\nA 的裁切與倍速保持固定", [
            appText(context, mode.label),
          ]);
        }
        result = await compute(
          solveThunderAlignment,
          PoseAlignmentRequest(
            a: a.processedPose!,
            b: b.processedPose!,
            aStart: a.trim.start.inMicroseconds / 1e6,
            aEnd: a.trim.end.inMicroseconds / 1e6,
            aRate: a.rate.value,
            bStart: searchStart,
            bEnd: searchEnd,
            searchFullRange: true,
            fixedBStart: lockTimeline ? searchStart : null,
            fixedBRate: lockRate ? originalRate.value : null,
            mirrorA: _mirrorA,
            mirrorB: _mirrorB,
          ),
        );
      }
    } catch (error) {
      failure ??= error;
    } finally {
      if (dialog.isActive) navigator.removeRoute(dialog);
      status.dispose();
      _poseAnalyzer = null;
      _activePoseAnalyzers.clear();
    }
    if (!mounted ||
        failure is PoseAnalysisCancelled ||
        (analyzer.cancelled && failure == null)) {
      return;
    }
    if (failure != null) {
      _showProjectMessage(
        appText(context, "骨架分析失敗：{0}", [appError(context, failure)]),
      );
      return;
    }
    if (result == null) {
      _showProjectMessage(
        appText(context, "已嘗試放寬條件，仍找不到可比較的骨架。請檢查骨架或調整固定影片的裁切區間。A、B 參數未變更。"),
      );
      return;
    }
    final suggestion = result;
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText(context, "AI 對齊建議")),
        content: Text(
          appText(
            context,
            "A 維持目前設定\nB：{0}\nB 起點：{1} 秒{2}\nB 終點：{3} 秒（{4}）\nB 倍速：{5}x{6}\n有效骨架：{7}%\n{8}姿勢差異：{9}（越低越相似）\n\n{10}人物交錯仍可能辨識錯人，請檢查骨架。尾端不一定同時播完。套用後可共同播放預覽，也可以復原。",
            [
              appText(context, mode.label),
              suggestion.bStart.toStringAsFixed(2),
              lockTimeline ? appText(context, "（保留）") : '',
              anchorEnd.toStringAsFixed(2),
              lockTimeline ? appText(context, "保留") : appText(context, "影片結尾"),
              suggestion.bRate.toStringAsFixed(3),
              lockRate ? appText(context, "（保留）") : '',
              (suggestion.coverage * 100).round(),
              suggestion.bestEffort
                  ? appText(context, "資料或重疊不足，這是盡力估計的結果，可套用預覽後微調。\n")
                  : '',
              suggestion.error.toStringAsFixed(3),
              suggestion.ambiguous
                  ? appText(context, "有其他相近答案，可能是重複動作，請特別檢查預覽。\n")
                  : '',
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(appText(context, "保留原設定")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(appText(context, "套用並預覽")),
          ),
        ],
      ),
    );
    if (apply == false && mounted) {
      EasterEggService.instance.engine.trigger('oracleRejected');
    }
    if (apply != true ||
        !mounted ||
        !identical(a, _trackA) ||
        !identical(b, _trackB)) {
      return;
    }
    final oldTrim = b.trim;
    final oldRate = b.rate;
    try {
      await b.player.setPlaybackSpeed(suggestion.bRate);
      if (!mounted) return;
      setState(() {
        _beforeAiTrack = b;
        _beforeAiTrim = oldTrim;
        _beforeAiRate = oldRate;
        b.rate = lockRate ? originalRate : PlaybackRate.ab(suggestion.bRate);
        b.trim = lockTimeline
            ? originalTrim
            : TimeRange(
                start: Duration(
                  microseconds: (suggestion.bStart * 1e6).round(),
                ),
                end: Duration(microseconds: (anchorEnd * 1e6).round()),
              );
        _alignmentLabel =
            'AI：B ${suggestion.bStart.toStringAsFixed(2)}s · ${suggestion.bRate.toStringAsFixed(3)}x';
      });
      await _seekBoth(0);
      if (mounted) await _toggleCommonPlayback();
    } catch (error) {
      if (mounted) {
        _showProjectMessage(
          appText(context, "預覽未完成，可按復原還原 B：{0}", [appError(context, error)]),
        );
      }
    }
  }

  Future<void> _undoAlignment() async {
    final b = _beforeAiTrack;
    if (b == null ||
        (!identical(b, _trackA) && !identical(b, _trackB)) ||
        _beforeAiTrim == null) {
      return;
    }
    await _beginCommonSeek(0);
    await b.player.setPlaybackSpeed(_beforeAiRate!.value);
    if (!mounted) return;
    setState(() {
      b.trim = _beforeAiTrim!;
      b.rate = _beforeAiRate!;
      _beforeAiTrack = null;
      _alignmentLabel = null;
    });
    await _seekBoth(0);
  }

  Duration get _sharedDuration {
    if (_previewBOnly) return _trackB!.toDomain().effectiveDuration;
    final a = _trackA;
    final b = _trackB;
    if (a != null && b != null) {
      return AnalysisProject(
        trackA: a.toDomain(),
        trackB: b.toDomain(),
        output: _output,
        audioSource: _audioSource,
        customAudio: _customAudio,
      ).sharedTimelineDuration;
    }
    return (a ?? b)?.toDomain().effectiveDuration ?? Duration.zero;
  }

  Future<void> _pick(bool isA) async {
    final source = await _picker.pick();
    if (source == null) return;
    final player = createLocalVideoController(
      source,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await player.initialize();
    await player.setVolume(
      _audioSource ==
              (isA ? AnalysisAudioSource.trackA : AnalysisAudioSource.trackB)
          ? 1
          : 0,
    );
    final state = _TrackState(
      source: source,
      player: player,
      seeker: LatestVideoSeeker(player),
      trim: TimeRange(start: Duration.zero, end: player.value.duration),
      rate: PlaybackRate.ab(1),
    );
    if (!mounted) {
      await player.dispose();
      return;
    }
    final old = isA ? _trackA : _trackB;
    setState(() {
      if (isA) {
        _trackA = state;
      } else {
        _trackB = state;
      }
      _progress = 0;
      _commonPlaying = false;
    });
    player.addListener(() => _onTrackTick(player, isA));
    old?.seeker.dispose();
    await old?.player.dispose();
    unawaited(_checkSameVideo());
    EasterEggService.instance.engine.clearProject('ab');
  }

  Future<void> _checkSameVideo() async {
    final a = _trackA;
    final b = _trackB;
    if (a == null || b == null) return;
    final same = await isSameVideo(a.source.path, b.source.path);
    if (mounted && identical(_trackA, a) && identical(_trackB, b) && same) {
      EasterEggService.instance.engine.trigger('duel');
    }
  }

  void _onTrackTick(VideoPlayerController player, bool isA) {
    if (!mounted) return;
    final track = isA ? _trackA : _trackB;
    if (track == null || !identical(track.player, player)) return;
    // During preparation/recovery, seek and native callbacks can still carry
    // old end positions. They must not end or advance the shared timeline.
    if (_startingCommonPlayback) {
      EasterEggService.instance.engine.listening('ab', {});
      return;
    }
    final eggs = EasterEggService.instance;
    if (eggs.foreground && eggs.page == 2 && !eggs.covered) {
      final playing = [_trackA, _trackB].any(
        (track) =>
            track != null &&
            track.player.value.isPlaying &&
            !track.player.value.isBuffering,
      );
      eggs.engine.listening('ab', {
        if (playing && _audioSource == AnalysisAudioSource.muted) 'silence',
      });
      if (playing) eggs.engine.projectPlayback('ab');
      eggs.engine.practice(
        'ab',
        (_trackA?.player.value.isPlaying ?? false) ||
            (_trackB?.player.value.isPlaying ?? false),
      );
    }

    if (_commonPlaying) {
      if (_previewBOnly &&
          isA &&
          player.value.position >= track.trim.end &&
          player.value.isPlaying) {
        unawaited(player.pause());
      }
      if ((!_previewBOnly || !isA) &&
          player.value.position >= _commonSourceEnd(track)) {
        _finishCommonPlayback();
        return;
      }
      if ((_previewBOnly ? !isA : (isA || _trackA == null)) &&
          _sharedDuration > Duration.zero) {
        final sourceElapsed = player.value.position - track.trim.start;
        final effectiveMicros = sourceElapsed.inMicroseconds / track.rate.value;
        setState(() {
          _progress = (effectiveMicros / _sharedDuration.inMicroseconds).clamp(
            0.0,
            1.0,
          );
        });
      } else {
        setState(() {});
      }
      return;
    }

    if (player.value.position >= track.trim.end && player.value.isPlaying) {
      player.pause();
    }
    setState(() {});
  }

  Duration _commonSourceEnd(_TrackState track) =>
      track.trim.clamp(track.trim.start + _sharedDuration * track.rate.value);

  Future<void> _finishCommonPlayback() async {
    if (_endingCommonPlayback) return;
    _endingCommonPlayback = true;
    _cancelCustomAudioSchedule();
    await Future.wait(
      [
        _trackA?.player,
        _trackB?.player,
      ].whereType<VideoPlayerController>().map((player) => player.pause()),
    );
    await _customAudioPlayer.pause();
    if (mounted) {
      setState(() {
        _progress = 1;
        _commonPlaying = false;
      });
    }
    _endingCommonPlayback = false;
  }

  Duration _sourcePosition(_TrackState track, double progress) {
    if (_previewBOnly) {
      return track.trim.clamp(
        track.trim.start + _sharedDuration * progress * track.rate.value,
      );
    }
    final a = _trackA;
    final b = _trackB;
    if (a != null && b != null) {
      final project = AnalysisProject(
        trackA: a.toDomain(),
        trackB: b.toDomain(),
        output: _output,
        audioSource: _audioSource,
        customAudio: _customAudio,
      );
      return project.sourcePositionAt(track.toDomain(), progress);
    }
    return track.trim.clamp(track.trim.start + track.trim.duration * progress);
  }

  Future<void> _seekBoth(double progress, {bool userScrub = false}) async {
    final a = _trackA;
    final b = _trackB;
    final aPosition = a == null ? null : _sourcePosition(a, progress);
    final bPosition = b == null ? null : _sourcePosition(b, progress);
    setState(() => _progress = progress);
    final operations = <Future<void>>[];
    if (a != null) {
      operations.add(
        userScrub
            ? a.seeker.seekWhileDragging(aPosition!)
            : a.seeker.seek(aPosition!),
      );
    }
    if (b != null) {
      operations.add(
        userScrub
            ? b.seeker.seekWhileDragging(bPosition!)
            : b.seeker.seek(bPosition!),
      );
    }
    if (_audioSource == AnalysisAudioSource.custom) {
      operations.add(_syncCustomAudio(_sharedDuration * progress));
    }
    await Future.wait(operations);
  }

  Future<void> _beginCommonSeek(double _) async {
    _commonPlaying = false;
    _cancelCustomAudioSchedule();
    await Future.wait(
      [
        _trackA?.player,
        _trackB?.player,
      ].whereType<VideoPlayerController>().map((player) => player.pause()),
    );
    await _customAudioPlayer.pause();
    if (mounted) setState(() {});
  }

  Future<void> _toggleCommonPlayback() async {
    if (_startingCommonPlayback || _endingCommonPlayback) return;
    final tracks = [_trackA, _trackB].whereType<_TrackState>().toList();
    if (tracks.isEmpty) return;
    if (_commonPlaying) {
      _cancelCustomAudioSchedule();
      await Future.wait([
        ...tracks.map((track) => track.player.pause()),
        _customAudioPlayer.pause(),
      ]);
      if (mounted) setState(() => _commonPlaying = false);
      return;
    }
    setState(() => _startingCommonPlayback = true);
    try {
      await Future.wait([
        ...tracks.map((track) => track.player.pause()),
        _customAudioPlayer.pause(),
      ]);
      _cancelCustomAudioSchedule();
      await _applySelectedAudioSource();
      // Reset the timeline here; the shared seek below must run only once.
      if (_progress >= 0.999) setState(() => _progress = 0);
      await Future.wait(
        tracks.map(
          (track) => track.seeker.seek(_sourcePosition(track, _progress)),
        ),
      );
      if (!mounted) return;
      setState(() => _commonPlaying = true);
      await startVideoPlaybackTogether(
        tracks
            .where(
              (track) =>
                  !_previewBOnly ||
                  identical(track, _trackB) ||
                  (_audioSource == AnalysisAudioSource.trackA &&
                      _sourcePosition(track, _progress) < track.trim.end),
            )
            .map((track) => track.player),
        isActive: () => mounted && _commonPlaying,
      );
      if (!mounted || !_commonPlaying) return;
      final clockTrack = _previewBOnly ? _trackB! : tracks.first;
      final currentPosition = await clockTrack.player.position;
      if (!mounted || !_commonPlaying) return;
      if (currentPosition != null && _sharedDuration > Duration.zero) {
        _progress =
            ((currentPosition - clockTrack.trim.start).inMicroseconds /
                    clockTrack.rate.value /
                    _sharedDuration.inMicroseconds)
                .clamp(0, 1);
      }
      if (_audioSource == AnalysisAudioSource.custom) {
        await _syncCustomAudio(_sharedDuration * _progress, play: true);
      }
    } catch (error) {
      if (mounted) {
        _commonPlaying = false;
        await Future.wait(tracks.map((track) => track.player.pause()));
        if (mounted) _showProjectMessage(appText(context, "影片尚未準備好，請再試一次。"));
      }
    } finally {
      if (mounted) setState(() => _startingCommonPlayback = false);
    }
  }

  Future<void> _toggleTrack(bool isA) async {
    final track = isA ? _trackA : _trackB;
    if (track == null) return;
    if (_commonPlaying) {
      _cancelCustomAudioSchedule();
      await Future.wait(
        [
          _trackA?.player,
          _trackB?.player,
        ].whereType<VideoPlayerController>().map((player) => player.pause()),
      );
      await _customAudioPlayer.pause();
      _commonPlaying = false;
    }
    if (track.player.value.isPlaying) {
      await track.player.pause();
    } else {
      await track.player.setVolume(1);
      if (track.player.value.position >= track.trim.end) {
        await track.seeker.seek(track.trim.start);
      }
      await track.player.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _changeTrim(bool isA, RangeValues values) async {
    final track = isA ? _trackA : _trackB;
    if (track == null) return;
    final old = track.trim;
    final start = Duration(milliseconds: values.start.round());
    final end = Duration(milliseconds: values.end.round());
    final startMoved = (start - old.start).abs() >= (end - old.end).abs();
    track.trim = TimeRange(start: start, end: end);
    _alignmentLabel = null;
    _beforeAiTrack = null;
    if (mounted) {
      setState(() {
        _progress = 0;
        _commonPlaying = false;
      });
    }
    await track.seeker.seekWhileDragging(startMoved ? start : end);
  }

  Future<void> _changeRate(bool isA, PlaybackRate rate) async {
    final track = isA ? _trackA : _trackB;
    if (track == null) return;
    track.rate = rate;
    _alignmentLabel = null;
    _beforeAiTrack = null;
    await track.player.setPlaybackSpeed(rate.value);
    if (mounted) setState(() => _progress = 0);
  }

  Future<void> _selectAudioSource(AnalysisAudioSource source) async {
    EasterEggService.instance.engine.listening('ab', {});
    if (source == AnalysisAudioSource.custom) {
      if (_commonPlaying) await _beginCommonSeek(_progress);
      if (_customAudio == null) {
        await _pickCustomAudio();
      } else {
        setState(() => _audioSource = AnalysisAudioSource.custom);
        await _applySelectedAudioSource();
        await _showCustomAudioEditor();
      }
      return;
    }
    _cancelCustomAudioSchedule();
    setState(() => _audioSource = source);
    await _applySelectedAudioSource();
  }

  Future<void> _pickCustomAudio() async {
    if (_commonPlaying) await _beginCommonSeek(_progress);
    final picked = await _audioPicker.pick();
    if (picked == null) return;
    try {
      final duration = await _customAudioPlayer.setFilePath(picked.path);
      if (duration == null || duration <= Duration.zero) {
        throw StateError('Could not read audio duration');
      }
      final source = picked.copyWith(
        mediaDuration: duration,
        trim: TimeRange(start: Duration.zero, end: duration),
      );
      if (!mounted) return;
      setState(() {
        _customAudio = source;
        _audioSource = AnalysisAudioSource.custom;
      });
      await _applySelectedAudioSource();
      await _syncCustomAudio(_sharedDuration * _progress, play: _commonPlaying);
      await _showCustomAudioEditor();
    } catch (error) {
      if (mounted) {
        _showProjectMessage(
          appText(context, "無法開啟自訂音源：{0}", [appError(context, error)]),
        );
      }
    }
  }

  Future<void> _showCustomAudioEditor() async {
    final source = _customAudio;
    if (source == null) return;
    final result = await showModalBottomSheet<_CustomAudioEditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CustomAudioTimelineEditor(
        source: source,
        timelineDuration: _sharedDuration,
      ),
    );
    if (result == null || !mounted) return;
    if (result.replaceSource) {
      await _pickCustomAudio();
      return;
    }
    setState(() => _customAudio = result.source);
    await _syncCustomAudio(_sharedDuration * _progress, play: _commonPlaying);
  }

  void _cancelCustomAudioSchedule() {
    _customAudioStartTimer?.cancel();
    _customAudioEndTimer?.cancel();
    _customAudioStartTimer = null;
    _customAudioEndTimer = null;
  }

  Future<void> _syncCustomAudio(
    Duration timelinePosition, {
    bool play = false,
  }) async {
    _cancelCustomAudioSchedule();
    final source = _customAudio;
    if (source == null || _audioSource != AnalysisAudioSource.custom) {
      await _customAudioPlayer.pause();
      return;
    }
    await _customAudioPlayer.pause();
    if (timelinePosition >= source.timelineEnd) {
      await _customAudioPlayer.seek(source.trim.end);
      return;
    }
    if (timelinePosition < source.timelineStart) {
      await _customAudioPlayer.seek(source.trim.start);
      if (!play) return;
      final delay = source.timelineStart - timelinePosition;
      _customAudioStartTimer = Timer(delay, () async {
        if (!_commonPlaying ||
            _audioSource != AnalysisAudioSource.custom ||
            !mounted) {
          return;
        }
        unawaited(_customAudioPlayer.play());
        _customAudioEndTimer = Timer(source.trim.duration, () {
          _customAudioPlayer.pause();
        });
      });
      return;
    }
    final elapsed = timelinePosition - source.timelineStart;
    await _customAudioPlayer.seek(source.trim.start + elapsed);
    if (!play) return;
    unawaited(_customAudioPlayer.play());
    _customAudioEndTimer = Timer(source.trim.duration - elapsed, () {
      _customAudioPlayer.pause();
    });
  }

  Future<void> _applySelectedAudioSource() => Future.wait([
    if (_trackA case final track?)
      track.player.setVolume(
        _audioSource == AnalysisAudioSource.trackA ? 1 : 0,
      ),
    if (_trackB case final track?)
      track.player.setVolume(
        _audioSource == AnalysisAudioSource.trackB ? 1 : 0,
      ),
    _customAudioPlayer.setVolume(
      _audioSource == AnalysisAudioSource.custom ? 1 : 0,
    ),
    if (_audioSource != AnalysisAudioSource.custom) _customAudioPlayer.pause(),
  ]);

  Future<void> _setLayout(_ComparisonLayout layout) async {
    setState(() => _layout = layout);
    if (_orientationLocked) await _applyOrientationLock();
  }

  Future<void> _toggleOrientationLock() async {
    setState(() => _orientationLocked = !_orientationLocked);
    if (_orientationLocked) {
      await _applyOrientationLock();
    } else {
      await SystemChrome.setPreferredOrientations([]);
    }
  }

  Future<void> _applyOrientationLock() => SystemChrome.setPreferredOrientations(
    _layout == _ComparisonLayout.vertical
        ? [DeviceOrientation.portraitUp]
        : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
  );

  Map<String, Object?> _trackProjectData(
    AnalysisTrack track,
    VideoSource savedSource,
  ) => {
    'source': {
      'id': savedSource.id,
      'path': savedSource.path,
      'label': savedSource.label,
    },
    'trimStartMs': track.trim.start.inMilliseconds,
    'trimEndMs': track.trim.end.inMilliseconds,
    'rate': track.rate.value,
  };

  Future<bool> _saveProject({bool showMessage = true}) async {
    if (_trackA == null && _trackB == null) return false;
    var name = _savedProjectName;
    if (_savedProjectId == null) {
      final labels = [
        _trackA?.source.label,
        _trackB?.source.label,
      ].whereType<String>().join(' + ');
      name = await requestProjectName(context, initialValue: labels);
      if (name == null || !mounted) return false;
    }
    try {
      final a = _trackA?.toDomain(), b = _trackB?.toDomain();
      final savedA = a == null
          ? null
          : await _projectMediaStore.persistVideo(a.source);
      final savedB = b == null
          ? null
          : await _projectMediaStore.persistVideo(b.source);
      final savedAudio = _customAudio == null
          ? null
          : await _projectMediaStore.persistAudio(_customAudio!);
      final project = await _projectStore.save(
        id: _savedProjectId,
        name: name!,
        mode: SavedProjectMode.analysis,
        data: {
          'trackA': a == null ? null : _trackProjectData(a, savedA!),
          'trackB': b == null ? null : _trackProjectData(b, savedB!),
          'progress': _progress,
          'mirrorA': _mirrorA,
          'mirrorB': _mirrorB,
          'layout': _layout.name,
          'output': _output.name,
          'audioSource': _audioSource.name,
          'customAudio': savedAudio == null
              ? null
              : {
                  'id': savedAudio.id,
                  'path': savedAudio.path,
                  'label': savedAudio.label,
                  'mediaDurationMs': savedAudio.mediaDuration.inMilliseconds,
                  'trimStartMs': savedAudio.trim.start.inMilliseconds,
                  'trimEndMs': savedAudio.trim.end.inMilliseconds,
                  'timelineStartMs': savedAudio.timelineStart.inMilliseconds,
                },
          'exportFolder': _exportFolder.path,
          'pose3dSettings': _pose3dSettings.toJson(),
        },
      );
      if (a != null && b != null && savedA != null && savedB != null) {
        AnalysisTrack savedTrack(AnalysisTrack t, VideoSource s) =>
            AnalysisTrack(
              source: s,
              mediaDuration: t.mediaDuration,
              trim: TimeRange(
                start: Duration(milliseconds: t.trim.start.inMilliseconds),
                end: Duration(milliseconds: t.trim.end.inMilliseconds),
              ),
              rate: t.rate,
            );
        await Pose3dJobs.instance.bindProject(
          project.id,
          AnalysisProject(
            trackA: a,
            trackB: b,
            output: AnalysisOutput.sideBySide,
          ),
          AnalysisProject(
            trackA: savedTrack(a, savedA),
            trackB: savedTrack(b, savedB),
            output: AnalysisOutput.sideBySide,
          ),
        );
      }
      if (!mounted) return true;
      setState(() {
        _savedProjectId = project.id;
        _savedProjectName = project.name;
      });
      if (showMessage) {
        _showProjectMessage(appText(context, "已儲存「{0}」", [project.name]));
      }
      return true;
    } catch (error) {
      if (mounted) {
        _showProjectMessage(
          appText(context, "儲存失敗：{0}", [appError(context, error)]),
        );
      }
      return false;
    }
  }

  Future<_TrackState?> _restoreTrack(Object? raw) async {
    if (raw == null) return null;
    final data = Map<String, Object?>.from(raw as Map);
    final sourceData = Map<String, Object?>.from(data['source'] as Map);
    final source = VideoSource(
      id: sourceData['id'] as String,
      path: sourceData['path'] as String,
      label: sourceData['label'] as String,
    );
    final player = createLocalVideoController(
      source,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await player.initialize();
    final rate = PlaybackRate.ab((data['rate'] as num).toDouble());
    await player.setPlaybackSpeed(rate.value);
    return _TrackState(
      source: source,
      player: player,
      seeker: LatestVideoSeeker(player),
      trim: TimeRange(
        start: Duration(milliseconds: data['trimStartMs'] as int),
        end: Duration(milliseconds: data['trimEndMs'] as int),
      ).normalizedWithin(player.value.duration),
      rate: rate,
    );
  }

  Future<void> _loadProject(SavedProject project) async {
    _TrackState? nextA;
    _TrackState? nextB;
    try {
      nextA = await _restoreTrack(project.data['trackA']);
      nextB = await _restoreTrack(project.data['trackB']);
      if (!mounted) {
        await nextA?.player.dispose();
        await nextB?.player.dispose();
        return;
      }
      await Future.wait(
        [
          _trackA?.player,
          _trackB?.player,
        ].whereType<VideoPlayerController>().map((player) => player.pause()),
      );
      final oldA = _trackA;
      final oldB = _trackB;
      final data = project.data;
      final layoutName = data['layout'] as String?;
      final outputName = data['output'] as String?;
      final audioSourceName = data['audioSource'] as String?;
      final customAudioData = data['customAudio'] == null
          ? null
          : Map<String, Object?>.from(data['customAudio'] as Map);
      var customAudio = customAudioData == null
          ? null
          : AnalysisCustomAudio(
              id: customAudioData['id'] as String,
              path: customAudioData['path'] as String,
              label: customAudioData['label'] as String,
              mediaDuration: Duration(
                milliseconds: (customAudioData['mediaDurationMs'] as int?) ?? 0,
              ),
              trim: TimeRange(
                start: Duration(
                  milliseconds: (customAudioData['trimStartMs'] as int?) ?? 0,
                ),
                end: Duration(
                  milliseconds: (customAudioData['trimEndMs'] as int?) ?? 0,
                ),
              ),
              timelineStart: Duration(
                milliseconds: (customAudioData['timelineStartMs'] as int?) ?? 0,
              ),
            );
      final folder = AnalysisGalleryFolder.tryParse(
        (data['exportFolder'] as String?) ?? '',
      );
      await _customAudioPlayer.pause();
      if (customAudio == null) {
        await _customAudioPlayer.stop();
      } else {
        final detectedDuration = await _customAudioPlayer.setFilePath(
          customAudio.path,
        );
        if (customAudio.mediaDuration <= Duration.zero &&
            detectedDuration != null) {
          customAudio = customAudio.copyWith(
            mediaDuration: detectedDuration,
            trim: TimeRange(start: Duration.zero, end: detectedDuration),
          );
        }
      }
      setState(() {
        _trackA = nextA;
        _trackB = nextB;
        _progress = ((data['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1);
        _commonPlaying = false;
        _mirrorA = (data['mirrorA'] as bool?) ?? false;
        _mirrorB = (data['mirrorB'] as bool?) ?? false;
        _layout =
            _ComparisonLayout.values
                .where((value) => value.name == layoutName)
                .firstOrNull ??
            _ComparisonLayout.vertical;
        _output =
            AnalysisOutput.values
                .where((value) => value.name == outputName)
                .firstOrNull ??
            AnalysisOutput.sideBySide;
        _audioSource =
            AnalysisAudioSource.values
                .where((value) => value.name == audioSourceName)
                .firstOrNull ??
            AnalysisAudioSource.trackB;
        _customAudio = customAudio;
        if (_audioSource == AnalysisAudioSource.custom && customAudio == null) {
          _audioSource = AnalysisAudioSource.trackB;
        }
        _exportFolder = folder ?? AnalysisGalleryFolder.defaultFolder;
        _orientationLocked = false;
        _savedProjectId = project.id;
        _savedProjectName = project.name;
        if (data['pose3dSettings'] != null) {
          _pose3dSettings = Pose3dSettings.fromJson(data['pose3dSettings']);
        }
      });
      if (nextA != null && nextB != null) {
        final snapshot = AnalysisProject(
          trackA: nextA.toDomain(),
          trackB: nextB.toDomain(),
          output: AnalysisOutput.sideBySide,
        );
        try {
          await Pose3dJobs.instance.bindProject(project.id, snapshot, snapshot);
        } catch (error) {
          if (mounted) {
            _showProjectMessage(
              appText(context, '儲存失敗：{0}', [appError(context, error)]),
            );
          }
        }
      }
      nextA?.player.addListener(() => _onTrackTick(nextA!.player, true));
      nextB?.player.addListener(() => _onTrackTick(nextB!.player, false));
      await SystemChrome.setPreferredOrientations([]);
      await _seekBoth(_progress);
      unawaited(_checkSameVideo());
      await _applySelectedAudioSource();
      oldA?.seeker.dispose();
      oldB?.seeker.dispose();
      await oldA?.player.dispose();
      await oldB?.player.dispose();
      if (!mounted) return;
      _showProjectMessage(appText(context, "已開啟「{0}」", [project.name]));
      EasterEggService.instance.projectLoaded('ab', project);
    } catch (error) {
      await nextA?.player.dispose();
      await nextB?.player.dispose();
      if (mounted) {
        _showProjectMessage(appText(context, "無法開啟專案，請確認 A、B 原始影片仍存在。"));
      }
    }
  }

  void _showProjectMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _export() async {
    final a = _trackA;
    final b = _trackB;
    if (a == null || b == null || _exporting) return;
    setState(() => _exporting = true);
    final previousProgress = _progress;
    try {
      final project = AnalysisProject(
        trackA: a.toDomain(),
        trackB: b.toDomain(),
        output: _output,
        audioSource: _audioSource,
        customAudio: _customAudio,
      );
      _cancelCustomAudioSchedule();
      setState(() => _commonPlaying = false);
      await Future.wait([
        a.player.pause(),
        b.player.pause(),
        _customAudioPlayer.pause(),
      ]);
      if (!mounted) return;
      final folder = _exportFolder;
      setState(() => _previewing = true);
      await _seekBoth(0);
      await _applySelectedAudioSource();
      if (!mounted) return;
      final route = MaterialPageRoute<bool>(
        builder: (_) => AnalysisExportPreviewScreen(
          project: project,
          playerA: a.player,
          playerB: b.player,
          onToggle: _toggleCommonPlayback,
          onSeekStart: _beginCommonSeek,
          onSeek: _seekBoth,
        ),
      );
      final confirmed = await Navigator.of(context).push(route);
      await _beginCommonSeek(0);
      await route.completed;
      if (!mounted) return;
      setState(() => _previewing = false);
      await _seekBoth(previousProgress);
      if (confirmed != true || !mounted) return;
      _showProjectMessage(appText(context, "正在製作正式畫質影片，請保持 Terpsichore 開啟…"));
      final result = await _exporter.export(AnalysisExportRequest(project));
      final path = switch (result) {
        AnalysisExported(:final path) => path,
        AnalysisExportUnsupported(:final reason) => throw StateError(reason),
        AnalysisExportFailed(:final reason) => throw StateError(reason),
      };
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appText(context, "影片已保存在 Terpsichore 本機資料夾。"))),
      );
      EasterEggService.instance.exportCompleted();
      if (project.output == AnalysisOutput.trackBOnly) {
        EasterEggService.instance.engine.trigger('solo');
      }
      final galleryResult = await _gallery.save(path, folder: folder);
      if (!mounted) return;
      if (galleryResult case AnalysisGallerySaveFailed(:final reason)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appText(context, "影片已輸出，但無法加入媒體瀏覽器：{0}", [
                appError(context, reason),
              ]),
            ),
          ),
        );
        return;
      }
      final shouldShare = await _askExportDestination(path, folder);
      if (shouldShare && mounted) await _shareExport(path);
    } catch (error) {
      if (mounted) {
        _showProjectMessage(
          appText(context, "無法輸出影片：{0}", [appError(context, error)]),
        );
      }
    } finally {
      _previewing = false;
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<bool> _askExportDestination(
    String path,
    AnalysisGalleryFolder folder,
  ) async {
    final fileName = File(path).uri.pathSegments.last;
    final savedLocation = Platform.isAndroid
        ? 'Movies/${folder.path}'
        : appText(context, "{0} 相簿", [folder.path]);
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(appText(context, "影片已加入媒體瀏覽器")),
            content: Text(
              appText(context, "{0}\n\n已儲存到 {1}。現在要選擇傳送目的地嗎？", [
                fileName,
                savedLocation,
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(appText(context, "留在媒體庫")),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.send_outlined),
                label: Text(appText(context, "選擇目的地")),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showExportSettings() async {
    final settings = await showDialog<_ExportSettings>(
      context: context,
      builder: (_) => _ExportSettingsDialog(
        initialOutput: _output,
        initialFolder: _exportFolder,
      ),
    );
    if (settings == null || !mounted) return;
    setState(() {
      _output = settings.output;
      _exportFolder = settings.folder;
    });
  }

  Future<void> _shareExport(String path) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'video/mp4')],
        title: 'Terpsichore A+B Analysis',
        text: appText(context, "Terpsichore 分析影片"),
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  void dispose() {
    _cancelPoseAnalysis();
    _cancelCustomAudioSchedule();
    _trackA?.seeker.dispose();
    _trackB?.seeker.dispose();
    _trackA?.player.dispose();
    _trackB?.player.dispose();
    _customAudioPlayer.dispose();
    if (_orientationLocked) SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLayout =
        MediaQuery.orientationOf(context) == Orientation.landscape
        ? _ComparisonLayout.horizontal
        : _layout;
    final tracks = <Widget>[
      _TrackCard(
        title: appText(context, "A・參考影片"),
        track: _trackA,
        onTogglePose: () => _togglePose(true),
        onPick: () => _pick(true),
        onTogglePlay: () => _toggleTrack(true),
        onTrimChanged: (values) => _changeTrim(true, values),
        onRateChanged: (rate) => _changeRate(true, rate),
        mirrored: _mirrorA,
        onToggleMirror: () {
          EasterEggService.instance.mirror(ab: true);
          setState(() => _mirrorA = !_mirrorA);
        },
        verticalControls: effectiveLayout == _ComparisonLayout.vertical,
      ),
      _TrackCard(
        title: appText(context, "B・我的影片"),
        track: _trackB,
        onTogglePose: () => _togglePose(false),
        onPick: () => _pick(false),
        onTogglePlay: () => _toggleTrack(false),
        onTrimChanged: (values) => _changeTrim(false, values),
        onRateChanged: (rate) => _changeRate(false, rate),
        mirrored: _mirrorB,
        onToggleMirror: () {
          EasterEggService.instance.mirror(ab: true);
          setState(() => _mirrorB = !_mirrorB);
        },
        verticalControls: effectiveLayout == _ComparisonLayout.vertical,
      ),
    ];

    return AbsorbPointer(
      absorbing: _startingCommonPlayback,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: Column(
            children: [
              _AnalysisToolbar(
                layout: effectiveLayout,
                orientationLocked: _orientationLocked,
                output: _output,
                exportFolder: _exportFolder,
                canExport: _trackA != null && _trackB != null && !_exporting,
                exporting: _exporting,
                onLayoutChanged: _setLayout,
                onToggleLock: _toggleOrientationLock,
                projectControls: SavedProjectControls(
                  mode: SavedProjectMode.analysis,
                  canSave: _trackA != null || _trackB != null,
                  onSave: () async {
                    await _saveProject();
                  },
                  onLoad: _loadProject,
                ),
                onOpenExportSettings: _showExportSettings,
                onExport: _export,
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Row(
                  children: [
                    Flexible(
                      flex: 2,
                      child: TextButton.icon(
                        onPressed:
                            _trackA != null &&
                                _trackB != null &&
                                !_exporting &&
                                _settingsReady
                            ? () => _runPoseAnalysis()
                            : null,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(
                          appText(context, "AI 對齊（固定 A）"),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: Pose3dJobs.instance,
                      builder: (context, _) => TextButton.icon(
                        key: const ValueKey('ab-pose3d'),
                        onPressed:
                            _trackA != null &&
                                _trackB != null &&
                                _poseAnalyzer == null &&
                                !_openingPose3d &&
                                !_exporting &&
                                _settingsReady
                            ? _openPose3d
                            : null,
                        icon: const Icon(Icons.view_in_ar, size: 18),
                        label: Text(
                          Pose3dJobs.instance.current?.busy == true
                              ? '3D Pose ${(Pose3dJobs.instance.current!.progress * 100).round()}%'
                              : '3D Pose',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: appText(context, "AI 設定"),
                      onPressed: _settingsReady && _poseAnalyzer == null
                          ? _showAiSettings
                          : null,
                      icon: const Icon(Icons.tune, size: 18),
                    ),
                    if (_alignmentLabel != null &&
                        (identical(_beforeAiTrack, _trackA) ||
                            identical(_beforeAiTrack, _trackB))) ...[
                      TextButton(
                        onPressed: _undoAlignment,
                        child: Text(appText(context, "復原")),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: effectiveLayout == _ComparisonLayout.horizontal
                    ? Row(
                        children: [
                          Expanded(child: tracks.first),
                          const SizedBox(width: 6),
                          Expanded(child: tracks.last),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: tracks.first),
                          const SizedBox(height: 6),
                          Expanded(child: tracks.last),
                        ],
                      ),
              ),
              const SizedBox(height: 4),
              _CommonTimeline(
                preparing: _startingCommonPlayback,
                playing: _commonPlaying,
                progress: _progress,
                duration: _sharedDuration,
                enabled: _trackA != null || _trackB != null,
                audioSource: _audioSource,
                customAudioLabel: _customAudio?.label,
                onToggle: _toggleCommonPlayback,
                onSeekStart: _beginCommonSeek,
                onSeek: (progress) => _seekBoth(progress, userScrub: true),
                onSeekEnd: _seekBoth,
                onAudioSourceChanged: _selectAudioSource,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _AnalysisToolbar extends StatelessWidget {
  const _AnalysisToolbar({
    required this.layout,
    required this.orientationLocked,
    required this.output,
    required this.exportFolder,
    required this.canExport,
    required this.exporting,
    required this.onLayoutChanged,
    required this.onToggleLock,
    required this.projectControls,
    required this.onOpenExportSettings,
    required this.onExport,
  });

  final _ComparisonLayout layout;
  final bool orientationLocked;
  final AnalysisOutput output;
  final AnalysisGalleryFolder exportFolder;
  final bool canExport;
  final bool exporting;
  final ValueChanged<_ComparisonLayout> onLayoutChanged;
  final VoidCallback onToggleLock;
  final Widget projectControls;
  final VoidCallback onOpenExportSettings;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SegmentedButton<_ComparisonLayout>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: _ComparisonLayout.vertical,
            icon: Icon(Icons.view_agenda_outlined, size: 18),
            tooltip: appText(context, "上下排列（直版）"),
          ),
          ButtonSegment(
            value: _ComparisonLayout.horizontal,
            icon: Icon(Icons.view_column_outlined, size: 18),
            tooltip: appText(context, "左右排列（橫版）"),
          ),
        ],
        selected: {layout},
        onSelectionChanged: (value) => onLayoutChanged(value.first),
      ),
      IconButton(
        tooltip: orientationLocked
            ? appText(context, "解除畫面鎖定")
            : appText(context, "鎖定目前版面方向"),
        onPressed: onToggleLock,
        icon: Icon(
          orientationLocked
              ? Icons.screen_lock_rotation
              : Icons.screen_rotation_outlined,
        ),
      ),
      projectControls,
      IconButton(
        tooltip: appText(context, "輸出設定：Movies/{0}", [exportFolder.path]),
        onPressed: onOpenExportSettings,
        icon: const Icon(Icons.tune),
      ),
      IconButton.filledTonal(
        tooltip: appText(context, "預覽合成與輸出影片"),
        onPressed: canExport ? onExport : null,
        icon: exporting
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_alt),
      ),
    ],
  );
}

final class _ExportSettings {
  const _ExportSettings({required this.output, required this.folder});

  final AnalysisOutput output;
  final AnalysisGalleryFolder folder;
}

final class _ExportSettingsDialog extends StatefulWidget {
  const _ExportSettingsDialog({
    required this.initialOutput,
    required this.initialFolder,
  });

  final AnalysisOutput initialOutput;
  final AnalysisGalleryFolder initialFolder;

  @override
  State<_ExportSettingsDialog> createState() => _ExportSettingsDialogState();
}

final class _ExportSettingsDialogState extends State<_ExportSettingsDialog> {
  late final TextEditingController _folderController;
  late AnalysisOutput _output;

  @override
  void initState() {
    super.initState();
    _folderController = TextEditingController(text: widget.initialFolder.path);
    _output = widget.initialOutput;
  }

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
  }

  void _submit() {
    final folder = AnalysisGalleryFolder.tryParse(_folderController.text);
    if (folder == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appText(context, "請輸入有效的資料夾名稱"))));
      return;
    }
    Navigator.pop(context, _ExportSettings(output: _output, folder: folder));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(appText(context, "輸出設定")),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<AnalysisOutput>(
          initialValue: _output,
          decoration: InputDecoration(labelText: appText(context, "影片內容")),
          items: [
            DropdownMenuItem(
              value: AnalysisOutput.sideBySide,
              child: Text(appText(context, "輸出 A+B")),
            ),
            DropdownMenuItem(
              value: AnalysisOutput.trackBOnly,
              child: Text(appText(context, "只輸出 B")),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _output = value);
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _folderController,
          decoration: InputDecoration(
            labelText: Platform.isAndroid
                ? appText(context, "輸出資料夾")
                : appText(context, "輸出相簿"),
            prefixText: Platform.isAndroid ? 'Movies/' : null,
            helperText: appText(context, "可輸入子資料夾，例如 Terpsichore/A+B"),
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(appText(context, "取消")),
      ),
      FilledButton(onPressed: _submit, child: Text(appText(context, "套用"))),
    ],
  );
}

final class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.title,
    required this.track,
    required this.onTogglePose,
    required this.onPick,
    required this.onTogglePlay,
    required this.onTrimChanged,
    required this.onRateChanged,
    required this.mirrored,
    required this.onToggleMirror,
    required this.verticalControls,
  });

  final String title;
  final _TrackState? track;
  final VoidCallback onTogglePose;
  final VoidCallback onPick;
  final VoidCallback onTogglePlay;
  final ValueChanged<RangeValues> onTrimChanged;
  final ValueChanged<PlaybackRate> onRateChanged;
  final bool mirrored;
  final VoidCallback onToggleMirror;
  final bool verticalControls;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _buildCard(context, constraints),
  );

  Widget _buildCard(BuildContext context, BoxConstraints constraints) {
    final narrow = constraints.maxWidth < 300;
    final stacked = verticalControls || narrow;
    final value = track;
    final poseFrame =
        (value?.useProcessedPose == true
                ? value?.processedPose ?? value?.pose
                : value?.pose)
            ?.at((value!.player.value.position.inMicroseconds) / 1e6);
    final video = ColoredBox(
      color: Colors.black,
      child: value == null
          ? Center(
              child: FilledButton.tonalIcon(
                onPressed: onPick,
                icon: const Icon(Icons.add_to_photos_outlined),
                label: Text(appText(context, "選擇影片")),
              ),
            )
          : Center(
              child: AspectRatio(
                aspectRatio: value.player.value.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.flip(
                      flipX: mirrored,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(value.player),
                          if (value.showPose) PoseOverlay(frame: poseFrame),
                        ],
                      ),
                    ),
                    if (value.showPose)
                      Positioned(
                        left: 4,
                        top: 4,
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Colors.black54,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Text(
                                poseFrame == null
                                    ? appText(context, "此時間未分析")
                                    : appText(context, "{0} · {1}/17 · 橘色為補點", [
                                        value.useProcessedPose
                                            ? appText(context, "平滑")
                                            : appText(context, "原始"),
                                        poseFrame.points
                                            .where((p) => p.score >= .15)
                                            .length,
                                      ]),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
    final trimSlider = value == null
        ? null
        : VideoTrimSlider(
            trim: value.trim,
            mediaDuration: value.player.value.duration,
            onChanged: onTrimChanged,
            onChangeEnd: (_) => value.seeker.endUserScrub(),
          );
    final controls = value == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (verticalControls && !narrow)
                  Row(
                    children: [
                      _TrackPlayButton(
                        title: title,
                        playing: value.player.value.isPlaying,
                        onPressed: onTogglePlay,
                      ),
                      Expanded(
                        child: PlaybackRateControl(
                          maximum: PlaybackRate.abMaximum,
                          value: value.rate,
                          onChanged: onRateChanged,
                        ),
                      ),
                    ],
                  )
                else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _TrackPlayButton(
                      title: title,
                      playing: value.player.value.isPlaying,
                      onPressed: onTogglePlay,
                    ),
                  ),
                  PlaybackRateControl(
                    maximum: PlaybackRate.abMaximum,
                    value: value.rate,
                    onChanged: onRateChanged,
                    showSlider: false,
                  ),
                ],
                if (stacked) trimSlider!,
                if (stacked) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      appText(context, "起點  {0}", [
                        formatDuration(value.trim.start),
                      ]),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      appText(context, "終點  {0}", [
                        formatDuration(value.trim.end),
                      ]),
                    ),
                  ),
                ] else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        appText(context, "起 {0}", [
                          formatDuration(value.trim.start),
                        ]),
                      ),
                      Text(
                        appText(context, "終 {0}", [
                          formatDuration(value.trim.end),
                        ]),
                      ),
                    ],
                  ),
                Text(
                  appText(context, "來源 {0}  ·  {1}x 後 {2}", [
                    _formatDuration(value.trim.duration),
                    value.rate.value.toStringAsFixed(2),
                    _formatDuration(value.toDomain().effectiveDuration),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (narrow)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Wrap(
                    children: [
                      if (value != null) ...[
                        IconButton(
                          tooltip: value.showPose
                              ? appText(context, "隱藏骨架")
                              : appText(context, "顯示骨架"),
                          onPressed: onTogglePose,
                          isSelected: value.showPose,
                          icon: const Icon(Icons.accessibility_new),
                        ),
                        IconButton(
                          tooltip: mirrored
                              ? appText(context, "取消鏡像")
                              : appText(context, "開啟鏡像"),
                          onPressed: onToggleMirror,
                          isSelected: mirrored,
                          icon: const Icon(Icons.flip),
                        ),
                      ],
                      IconButton(
                        tooltip: value == null
                            ? appText(context, "選擇影片")
                            : appText(context, "更換影片"),
                        onPressed: onPick,
                        icon: const Icon(Icons.video_library_outlined),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 38,
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (value != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: value.showPose
                          ? appText(context, "隱藏骨架")
                          : appText(context, "顯示骨架"),
                      onPressed: onTogglePose,
                      isSelected: value.showPose,
                      icon: const Icon(Icons.accessibility_new),
                    ),
                  if (value != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: mirrored
                          ? appText(context, "取消鏡像")
                          : appText(context, "開啟鏡像"),
                      onPressed: onToggleMirror,
                      isSelected: mirrored,
                      icon: const Icon(Icons.flip),
                    ),
                  TextButton(
                    onPressed: onPick,
                    child: Text(
                      value == null
                          ? appText(context, "選擇")
                          : appText(context, "更換"),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: controls == null
                ? video
                : stacked
                ? Column(
                    children: [
                      Expanded(child: video),
                      Flexible(child: SingleChildScrollView(child: controls)),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(flex: 3, child: video),
                            const VerticalDivider(width: 2, thickness: 2),
                            Expanded(
                              flex: 2,
                              child: SingleChildScrollView(child: controls),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 44, child: trimSlider!),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

final class _TrackPlayButton extends StatelessWidget {
  const _TrackPlayButton({
    required this.title,
    required this.playing,
    required this.onPressed,
  });

  final String title;
  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    visualDensity: VisualDensity.compact,
    tooltip: appText(context, "{0} 單獨播放", [title]),
    onPressed: onPressed,
    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
  );
}

final class _CommonTimeline extends StatelessWidget {
  const _CommonTimeline({
    required this.preparing,
    required this.playing,
    required this.progress,
    required this.duration,
    required this.enabled,
    required this.audioSource,
    required this.customAudioLabel,
    required this.onToggle,
    required this.onSeekStart,
    required this.onSeek,
    required this.onSeekEnd,
    required this.onAudioSourceChanged,
  });

  final bool preparing;
  final bool playing;
  final double progress;
  final Duration duration;
  final bool enabled;
  final AnalysisAudioSource audioSource;
  final String? customAudioLabel;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSeekEnd;
  final ValueChanged<AnalysisAudioSource> onAudioSourceChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          IconButton.filled(
            tooltip: preparing
                ? appText(context, "準備共同播放")
                : appText(context, "共同播放"),
            onPressed: enabled ? onToggle : null,
            icon: preparing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(playing ? Icons.pause : Icons.play_arrow),
          ),
          PopupMenuButton<AnalysisAudioSource>(
            tooltip: switch (audioSource) {
              AnalysisAudioSource.trackA => appText(
                context,
                "音源：A（只擷取 A 的選取片段）",
              ),
              AnalysisAudioSource.trackB => appText(
                context,
                "音源：B（只擷取 B 的選取片段）",
              ),
              AnalysisAudioSource.custom => appText(context, "自訂音源：{0}", [
                customAudioLabel ?? appText(context, "尚未選擇"),
              ]),
              AnalysisAudioSource.muted => appText(context, "音源：靜音"),
            },
            initialValue: audioSource,
            onSelected: onAudioSourceChanged,
            icon: audioSource == AnalysisAudioSource.muted
                ? const Icon(Icons.volume_off_outlined)
                : audioSource == AnalysisAudioSource.custom
                ? const Icon(Icons.audio_file_outlined)
                : Badge(
                    label: Text(
                      audioSource == AnalysisAudioSource.trackA ? 'A' : 'B',
                    ),
                    child: const Icon(Icons.audiotrack),
                  ),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: AnalysisAudioSource.trackA,
                checked: audioSource == AnalysisAudioSource.trackA,
                child: ListTile(
                  title: Text(appText(context, "使用 A 音源")),
                  subtitle: Text(appText(context, "只取 A 目前選取的片段")),
                ),
              ),
              CheckedPopupMenuItem(
                value: AnalysisAudioSource.trackB,
                checked: audioSource == AnalysisAudioSource.trackB,
                child: ListTile(
                  title: Text(appText(context, "使用 B 音源")),
                  subtitle: Text(appText(context, "只取 B 目前選取的片段")),
                ),
              ),
              CheckedPopupMenuItem(
                value: AnalysisAudioSource.custom,
                checked: audioSource == AnalysisAudioSource.custom,
                child: ListTile(
                  title: Text(appText(context, "自訂音源")),
                  subtitle: Text(
                    customAudioLabel ?? appText(context, "選擇其他音訊檔"),
                  ),
                ),
              ),
              CheckedPopupMenuItem(
                value: AnalysisAudioSource.muted,
                checked: audioSource == AnalysisAudioSource.muted,
                child: ListTile(
                  title: Text(appText(context, "不要聲音")),
                  subtitle: Text(appText(context, "輸出靜音影片")),
                ),
              ),
            ],
          ),
          Expanded(
            child: PrecisionScrubSlider(
              position: duration * progress,
              duration: duration,
              onChangeStart: enabled
                  ? (position) => onSeekStart(
                      position.inMicroseconds / duration.inMicroseconds,
                    )
                  : (_) {},
              onChanged: enabled
                  ? (position) => onSeek(
                      position.inMicroseconds / duration.inMicroseconds,
                    )
                  : (_) {},
              onChangeEnd: enabled
                  ? (position) => onSeekEnd(
                      position.inMicroseconds / duration.inMicroseconds,
                    )
                  : null,
            ),
          ),
        ],
      ),
      Text(
        '${_formatDuration(duration * progress)} / ${_formatDuration(duration)}',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    ],
  );
}

final class _CustomAudioEditResult {
  const _CustomAudioEditResult(this.source) : replaceSource = false;
  const _CustomAudioEditResult.replace() : source = null, replaceSource = true;

  final AnalysisCustomAudio? source;
  final bool replaceSource;
}

final class _CustomAudioTimelineEditor extends StatefulWidget {
  const _CustomAudioTimelineEditor({
    required this.source,
    required this.timelineDuration,
  });

  final AnalysisCustomAudio source;
  final Duration timelineDuration;

  @override
  State<_CustomAudioTimelineEditor> createState() =>
      _CustomAudioTimelineEditorState();
}

final class _CustomAudioTimelineEditorState
    extends State<_CustomAudioTimelineEditor> {
  final AudioPlayer _preview = AudioPlayer();
  StreamSubscription<PlayerState>? _playerSubscription;
  late RangeValues _trim;
  late double _timelineStartMs;
  bool _ready = false;
  bool _playing = false;

  double get _mediaMax => widget.source.mediaDuration.inMilliseconds
      .toDouble()
      .clamp(1, double.infinity)
      .toDouble();

  double get _timelineMax => widget.timelineDuration.inMilliseconds
      .toDouble()
      .clamp(1, double.infinity)
      .toDouble();

  @override
  void initState() {
    super.initState();
    _trim = RangeValues(
      widget.source.trim.start.inMilliseconds.toDouble().clamp(0, _mediaMax),
      widget.source.trim.end.inMilliseconds.toDouble().clamp(0, _mediaMax),
    );
    _timelineStartMs = widget.source.timelineStart.inMilliseconds
        .toDouble()
        .clamp(0, _timelineMax);
    _playerSubscription = _preview.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing =
          state.playing && state.processingState != ProcessingState.completed;
      if (_playing != playing) setState(() => _playing = playing);
    });
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    await _preview.setFilePath(widget.source.path);
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _togglePreview() async {
    if (!_ready) return;
    if (_playing) {
      await _preview.pause();
      return;
    }
    final start = Duration(milliseconds: _trim.start.round());
    final end = Duration(milliseconds: _trim.end.round());
    await _preview.setClip(start: start, end: end);
    await _preview.seek(Duration.zero);
    unawaited(_preview.play());
  }

  Future<void> _stopPreview() async {
    if (_playing) await _preview.pause();
  }

  AnalysisCustomAudio get _result => widget.source.copyWith(
    trim: TimeRange(
      start: Duration(milliseconds: _trim.start.round()),
      end: Duration(milliseconds: _trim.end.round()),
    ),
    timelineStart: Duration(milliseconds: _timelineStartMs.round()),
  );

  @override
  void dispose() {
    _playerSubscription?.cancel();
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText(context, "自訂音源時間軸"),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                widget.source.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              Text(
                appText(context, "音源擷取範圍  {0} – {1}", [
                  _formatDuration(Duration(milliseconds: _trim.start.round())),
                  _formatDuration(Duration(milliseconds: _trim.end.round())),
                ]),
              ),
              RangeSlider(
                values: _trim,
                max: _mediaMax,
                labels: RangeLabels(
                  _formatDuration(Duration(milliseconds: _trim.start.round())),
                  _formatDuration(Duration(milliseconds: _trim.end.round())),
                ),
                onChanged: (values) {
                  _stopPreview();
                  if (values.end - values.start < 100) return;
                  setState(() => _trim = values);
                },
              ),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _ready ? _togglePreview : null,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                    label: Text(
                      _playing
                          ? appText(context, "暫停試聽")
                          : appText(context, "試聽選取片段"),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    appText(context, "共 {0}", [
                      _formatDuration(_result.trim.duration),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                appText(context, "放入 A+B 時間軸的位置  {0}", [
                  _formatDuration(
                    Duration(milliseconds: _timelineStartMs.round()),
                  ),
                ]),
              ),
              Slider(
                value: _timelineStartMs,
                max: _timelineMax,
                label: _formatDuration(
                  Duration(milliseconds: _timelineStartMs.round()),
                ),
                onChanged: (value) => setState(() => _timelineStartMs = value),
              ),
              _CustomAudioTimelinePreview(
                timelineDuration: widget.timelineDuration,
                source: _result,
              ),
              const SizedBox(height: 8),
              Text(
                appText(context, "套用後可用下方「共同播放」預覽影片與外來音源的同步效果。"),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      const _CustomAudioEditResult.replace(),
                    ),
                    icon: const Icon(Icons.audio_file_outlined),
                    label: Text(appText(context, "更換音源")),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(appText(context, "取消")),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, _CustomAudioEditResult(_result)),
                    child: Text(appText(context, "套用")),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _CustomAudioTimelinePreview extends StatelessWidget {
  const _CustomAudioTimelinePreview({
    required this.timelineDuration,
    required this.source,
  });

  final Duration timelineDuration;
  final AnalysisCustomAudio source;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final totalMs = timelineDuration.inMilliseconds.clamp(1, 1 << 62);
      final left =
          constraints.maxWidth *
          (source.timelineStart.inMilliseconds / totalMs).clamp(0, 1);
      final available = constraints.maxWidth - left;
      final maxWidth = available.clamp(4.0, constraints.maxWidth).toDouble();
      final width =
          (constraints.maxWidth *
                  (source.trim.duration.inMilliseconds / totalMs))
              .clamp(4.0, maxWidth)
              .toDouble();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'A+B  0:00.0 — ${_formatDuration(timelineDuration)}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: left,
                  top: 25,
                  width: width,
                  height: 22,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Center(
                      child: Text(
                        appText(context, "外來音源"),
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  final tenths = duration.inMilliseconds.remainder(1000) ~/ 100;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
}
