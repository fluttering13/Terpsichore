import 'package:terpsichore/infrastructure/engagement/easter_egg_service.dart';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/learning_mode/eight_count_grid.dart';
import '../../../core/learning_mode/learning_session.dart';
import '../../../core/learning_mode/loop_decision.dart';
import '../../../core/learning_mode/recording_output.dart';
import '../../../core/saved_projects/saved_project.dart';
import '../../../core/shared_video_playback/playback_rate.dart';
import '../../../core/shared_video_playback/time_range.dart';
import '../../../core/shared_video_playback/video_source.dart';
import '../../../infrastructure/media/local_video_picker.dart';
import '../../../infrastructure/media/recorded_video_store.dart';
import '../../../infrastructure/engagement/emotion_backmail_service.dart';
import '../../../infrastructure/saved_projects/local_saved_project_store.dart';
import '../../../infrastructure/saved_projects/project_media_store.dart';
import '../../../infrastructure/video_playback/latest_video_seeker.dart';
import '../../../infrastructure/video_playback/local_video_controller.dart';
import '../widgets/front_camera_panel.dart';
import '../widgets/playback_rate_control.dart';
import '../widgets/precision_scrub_slider.dart';
import '../widgets/saved_project_controls.dart';
import '../widgets/time_text.dart';

final class LearningModeScreen extends StatefulWidget {
  const LearningModeScreen({super.key});

  @override
  State<LearningModeScreen> createState() => _LearningModeScreenState();
}

final class _LearningModeScreenState extends State<LearningModeScreen> {
  static const _picker = LocalVideoPicker();
  static const _loopPolicy = LearningLoopPolicy();
  static const _recordedVideoStore = RecordedVideoStore();
  static final _projectStore = LocalSavedProjectStore.instance;
  static const _projectMediaStore = ProjectMediaStore();

  VideoPlayerController? _player;
  LatestVideoSeeker? _seeker;
  VideoSource? _source;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlaybackRate _rate = PlaybackRate(1);
  TimeRange _loop = TimeRange(start: Duration.zero, end: Duration.zero);
  bool _repeat = false;
  Duration _rest = Duration.zero;
  bool _handlingLoop = false;
  int? _restCountdownSeconds;
  int _restCountdownGeneration = 0;
  bool _settingsOpen = false;
  Duration? _firstEightStart;
  EightCountGrid? _grid;
  int _loopStartEight = 1;
  int _loopEndEight = 1;
  bool _recording = false;
  bool _showCameraB = false;
  bool _mirrorA = false;
  RecordingOutput _recordingOutput = RecordingOutput.dancerOnly;
  String? _savedProjectId;
  String? _savedProjectName;

  Timer? _eggTimer;
  bool _eggPlaybackActive = false;
  TimeRange? _loopEditStart;
  String get _eggSegment =>
      '${_source?.path}:${_loop.start.inMicroseconds}:${_loop.end.inMicroseconds}';

  @override
  void initState() {
    super.initState();
    _eggTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _sampleEggs(),
    );
  }

  void _sampleEggs() {
    final service = EasterEggService.instance;
    final player = _player;
    if (!service.learningVisible ||
        player == null ||
        !player.value.isInitialized) {
      return;
    }
    final continuingLoop =
        _repeat && player.value.position >= _loop.end && _eggPlaybackActive;
    _eggPlaybackActive =
        player.value.isPlaying || _handlingLoop || continuingLoop;
    final engine = service.engine;
    engine.segment('learning', _eggSegment);
    engine.learningFrame(
      '${_source?.path}:${player.value.position.inMicroseconds}',
      playing: _eggPlaybackActive,
      rate: _rate.value,
    );
    engine.practice('learning', _eggPlaybackActive || _recording);
  }

  Future<void> _pickVideo() async {
    final source = await _picker.pick();
    if (source == null) return;
    final next = createLocalVideoController(source);
    await next.initialize();
    await next.setPlaybackSpeed(_rate.value);
    next.addListener(_onPlayerChanged);
    final old = _player;
    final oldSeeker = _seeker;
    if (!mounted) {
      await next.dispose();
      return;
    }
    _eggPlaybackActive = false;
    EasterEggService.instance.engine.clearPause();
    _restCountdownGeneration++;
    setState(() {
      _source = source;
      _player = next;
      _seeker = LatestVideoSeeker(next);
      _duration = next.value.duration;
      _position = Duration.zero;
      _loop = TimeRange(start: Duration.zero, end: _duration);
      _firstEightStart = null;
      _grid = null;
      _loopStartEight = 1;
      _loopEndEight = 1;
      _restCountdownSeconds = null;
    });
    oldSeeker?.dispose();
    old?.removeListener(_onPlayerChanged);
    await old?.dispose();
  }

  Future<void> _saveProject() async {
    final source = _source;
    if (source == null) return;
    var name = _savedProjectName;
    if (_savedProjectId == null) {
      name = await requestProjectName(context, initialValue: source.label);
      if (name == null || !mounted) return;
    }
    try {
      final savedSource = await _projectMediaStore.persistVideo(source);
      final grid = _grid;
      final project = await _projectStore.save(
        id: _savedProjectId,
        name: name!,
        mode: SavedProjectMode.learning,
        data: {
          'source': {
            'id': savedSource.id,
            'path': savedSource.path,
            'label': savedSource.label,
          },
          'positionMs': _position.inMilliseconds,
          'rate': _rate.value,
          'loopStartMs': _loop.start.inMilliseconds,
          'loopEndMs': _loop.end.inMilliseconds,
          'repeat': _repeat,
          'restMs': _rest.inMilliseconds,
          'firstEightStartMs': grid?.firstEightStart.inMilliseconds,
          'firstEightEndMs': grid?.firstEightEnd.inMilliseconds,
          'loopStartEight': _loopStartEight,
          'loopEndEight': _loopEndEight,
          'showCameraB': _showCameraB,
          'mirrorA': _mirrorA,
          'recordingOutput': _recordingOutput.name,
        },
      );
      if (!mounted) return;
      setState(() {
        _savedProjectId = project.id;
        _savedProjectName = project.name;
      });
      _showProjectMessage('已儲存「${project.name}」');
    } catch (error) {
      if (mounted) _showProjectMessage('儲存失敗：$error');
    }
  }

  Future<void> _openProjectLibrary() async {
    final project = await showSavedProjectLibrary(
      context,
      mode: SavedProjectMode.learning,
    );
    if (project != null) await _loadProject(project);
  }

  Future<void> _loadProject(SavedProject project) async {
    try {
      final data = project.data;
      final sourceData = Map<String, Object?>.from(data['source'] as Map);
      final source = VideoSource(
        id: sourceData['id'] as String,
        path: sourceData['path'] as String,
        label: sourceData['label'] as String,
      );
      final next = createLocalVideoController(source);
      await next.initialize();
      final rate = PlaybackRate((data['rate'] as num).toDouble());
      await next.setPlaybackSpeed(rate.value);
      final duration = next.value.duration;
      final loop = TimeRange(
        start: Duration(milliseconds: data['loopStartMs'] as int),
        end: Duration(milliseconds: data['loopEndMs'] as int),
      ).normalizedWithin(duration);
      final position = loop.clamp(
        Duration(
          milliseconds:
              (data['positionMs'] as int?) ?? loop.start.inMilliseconds,
        ),
      );
      await next.seekTo(position);
      final firstStart = data['firstEightStartMs'] as int?;
      final firstEnd = data['firstEightEndMs'] as int?;
      final grid =
          firstStart != null && firstEnd != null && firstEnd > firstStart
          ? EightCountGrid(
              firstEightStart: Duration(milliseconds: firstStart),
              firstEightEnd: Duration(milliseconds: firstEnd),
            )
          : null;
      if (!mounted) {
        await next.dispose();
        return;
      }
      final old = _player;
      final oldSeeker = _seeker;
      next.addListener(_onPlayerChanged);
      _eggPlaybackActive = false;
      EasterEggService.instance.engine.clearPause();
      _restCountdownGeneration++;
      setState(() {
        _source = source;
        _player = next;
        _seeker = LatestVideoSeeker(next);
        _duration = duration;
        _position = position;
        _rate = rate;
        _loop = loop;
        _repeat = (data['repeat'] as bool?) ?? false;
        _rest = Duration(milliseconds: (data['restMs'] as int?) ?? 0);
        _firstEightStart = grid?.firstEightStart;
        _grid = grid;
        _loopStartEight = (data['loopStartEight'] as int?) ?? 1;
        _loopEndEight = (data['loopEndEight'] as int?) ?? 1;
        _showCameraB = (data['showCameraB'] as bool?) ?? false;
        _mirrorA = (data['mirrorA'] as bool?) ?? false;
        _recording = false;
        _recordingOutput = _recordingOutputFromName(
          data['recordingOutput'] as String?,
        );
        _restCountdownSeconds = null;
        _savedProjectId = project.id;
        _savedProjectName = project.name;
      });
      oldSeeker?.dispose();
      old?.removeListener(_onPlayerChanged);
      await old?.dispose();
      _showProjectMessage('已開啟「${project.name}」');
    } catch (error) {
      if (mounted) _showProjectMessage('無法開啟專案，請確認原始影片仍存在。');
    }
  }

  RecordingOutput _recordingOutputFromName(String? name) =>
      RecordingOutput.values.where((value) => value.name == name).firstOrNull ??
      RecordingOutput.dancerOnly;

  void _showProjectMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _onPlayerChanged() {
    final player = _player;
    if (!mounted || player == null || !player.value.isInitialized) return;
    final nextPosition = player.value.position;
    if (nextPosition != _position) setState(() => _position = nextPosition);
    _sampleEggs();
    _handleLoop(nextPosition);
  }

  Future<void> _handleLoop(Duration position) async {
    if (_handlingLoop || _source == null || _loop.end == Duration.zero) return;
    final decision = _loopPolicy.evaluate(
      LearningSession(
        video: _source!,
        rate: _rate,
        loop: _loop,
        repeatEnabled: _repeat,
        restBetweenLoops: _rest,
        eightCountGrid: _grid,
      ),
      position,
    );
    if (decision.type == LoopActionType.none) return;
    _handlingLoop = true;
    if (EasterEggService.instance.learningVisible && _eggPlaybackActive) {
      EasterEggService.instance.engine.completedLoop('learning', _eggSegment);
    }
    final player = _player;
    try {
      if (decision.type == LoopActionType.pauseThenRestart) {
        await player?.pause();
        final completed = await _showRestCountdown(decision.wait, player);
        if (!completed) return;
      }
      if (mounted && identical(player, _player)) {
        await player?.seekTo(decision.seekTo!);
        await player?.play();
      }
    } finally {
      _handlingLoop = false;
    }
  }

  Future<bool> _showRestCountdown(
    Duration wait,
    VideoPlayerController? player,
  ) async {
    final generation = ++_restCountdownGeneration;
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < wait) {
      if (!mounted ||
          generation != _restCountdownGeneration ||
          !identical(player, _player)) {
        return false;
      }
      final remaining = wait - stopwatch.elapsed;
      final seconds = visibleRestCountdownSeconds(remaining);
      if (_restCountdownSeconds != seconds) {
        setState(() => _restCountdownSeconds = seconds);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted ||
        generation != _restCountdownGeneration ||
        !identical(player, _player)) {
      return false;
    }
    setState(() => _restCountdownSeconds = null);
    return true;
  }

  Future<void> _setRate(PlaybackRate rate) async {
    EasterEggService.instance.engine.rate(_rate.value, rate.value);
    setState(() => _rate = rate);
    await _player?.setPlaybackSpeed(rate.value);
  }

  Future<void> _onLoopChanged(RangeValues values) async {
    final old = _loop;
    final next = TimeRange(
      start: Duration(milliseconds: values.start.round()),
      end: Duration(milliseconds: values.end.round()),
    );
    final startMoved = next.start != old.start;
    setState(() => _loop = next);
    await _seeker?.seekWhileDragging(startMoved ? next.start : next.end);
  }

  void _markEightBoundary() {
    if (_firstEightStart == null) {
      setState(() {
        _firstEightStart = _position;
        _grid = null;
      });
      return;
    }
    if (_position <= _firstEightStart!) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('第一個八的終點必須在起點之後')));
      return;
    }
    final firstEightStart = _firstEightStart!;
    final firstEightEnd = _position;
    setState(() {
      _grid = EightCountGrid(
        firstEightStart: firstEightStart,
        firstEightEnd: firstEightEnd,
      );
      _loopStartEight = 1;
      _loopEndEight = 1;
      _loop = TimeRange(start: firstEightStart, end: firstEightEnd);
    });
    _player?.seekTo(firstEightStart);
  }

  Future<void> _selectEightRange(int startEight, int endEight) async {
    final grid = _grid;
    if (grid == null) return;
    final maximum = grid.availableEightCount(_duration);
    if (maximum == 0) return;
    final safeStart = startEight.clamp(1, maximum);
    final safeEnd = endEight.clamp(safeStart, maximum);
    final range = grid.rangeForEights(
      startEight: safeStart,
      endEight: safeEnd,
      mediaDuration: _duration,
    );
    if (range.start != _loop.start || range.end != _loop.end) {
      EasterEggService.instance.count('sculpt', 11, rapid: true);
    }
    setState(() {
      _loopStartEight = safeStart;
      _loopEndEight = safeEnd;
      _loop = range;
    });
    await _player?.seekTo(range.start);
  }

  Future<void> _handleRecording(XFile file) async {
    try {
      final path = await _recordedVideoStore.persist(file);
      EasterEggService.instance.exportCompleted();
      if (!mounted) return;
      final message = _recordingOutput == RecordingOutput.dancerOnly
          ? '已儲存 B：$path'
          : '已儲存 B；A+B 合成引擎將在下一階段接入';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('錄影儲存失敗：$error')));
    }
  }

  @override
  void dispose() {
    _eggTimer?.cancel();
    _restCountdownGeneration++;
    _seeker?.dispose();
    _player?.removeListener(_onPlayerChanged);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final english =
        EmotionBackmailService.language.value == AppLanguage.english;
    if (player == null) {
      return _EmptyLearningState(
        onPickVideo: _pickVideo,
        onOpenProjects: _openProjectLibrary,
      );
    }
    final beat = _grid?.positionAt(_position);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _LearningCanvas(
                      player: player,
                      mirrorA: _mirrorA,
                      showCameraB: _showCameraB,
                      recording: _recording,
                      onRecordingChanged: (file) {
                        if (file != null) _handleRecording(file);
                      },
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filledTonal(
                          tooltip: english
                              ? (_mirrorA ? 'Unmirror A' : 'Mirror A')
                              : (_mirrorA ? '取消 A 鏡像' : '鏡像翻轉 A'),
                          isSelected: _mirrorA,
                          onPressed: () {
                            EasterEggService.instance.mirror();
                            setState(() => _mirrorA = !_mirrorA);
                          },
                          icon: const Icon(Icons.flip),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: _recording
                              ? null
                              : () {
                                  EasterEggService.instance.count('camera', 11);
                                  setState(() => _showCameraB = !_showCameraB);
                                },
                          icon: Icon(
                            _showCameraB
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          label: Text(_showCameraB ? '關閉 B' : '顯示 B'),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: _showCameraB
                              ? (_recording ? '停止錄影' : '開始錄影')
                              : '請先顯示 B 鏡頭',
                          style: IconButton.styleFrom(
                            backgroundColor: _recording ? Colors.red : null,
                          ),
                          onPressed: _showCameraB
                              ? () => setState(() => _recording = !_recording)
                              : null,
                          icon: Icon(
                            _recording ? Icons.stop : Icons.fiber_manual_record,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_restCountdownSeconds case final seconds?)
                    Positioned.fill(
                      child: _RestCountdownOverlay(seconds: seconds),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 68,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        IconButton.filled(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => player.value.isPlaying
                              ? player.pause()
                              : player.play(),
                          icon: Icon(
                            player.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                        ),
                        Expanded(
                          child: PrecisionScrubSlider(
                            position: _position,
                            duration: _duration,
                            onChangeStart: (_) => player.pause(),
                            onChanged: (position) =>
                                _seeker?.seekWhileDragging(position),
                            onChangeEnd: (position) => _seeker?.seek(position),
                          ),
                        ),
                        TimeText(_position),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      beat?.label ?? '八拍未校正',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
            _BottomLearningSettings(
              expanded: _settingsOpen,
              onToggle: () => setState(() => _settingsOpen = !_settingsOpen),
              projectControls: SavedProjectControls(
                mode: SavedProjectMode.learning,
                canSave: true,
                onSave: _saveProject,
                onLoad: _loadProject,
              ),
              child: _SettingsPanel(
                duration: _duration,
                loop: _loop,
                rate: _rate,
                repeat: _repeat,
                rest: _rest,
                firstEightStart: _firstEightStart,
                grid: _grid,
                loopStartEight: _loopStartEight,
                loopEndEight: _loopEndEight,
                recordingOutput: _recordingOutput,
                onPickVideo: _pickVideo,
                onRateChanged: _setRate,
                onLoopChanged: _onLoopChanged,
                onLoopChangeStart: (_) => _loopEditStart = _loop,
                onLoopChangeEnd: (_) {
                  unawaited(_seeker?.endUserScrub());
                  final start = _loopEditStart;
                  if (start != null &&
                      (start.start != _loop.start || start.end != _loop.end)) {
                    EasterEggService.instance.count('sculpt', 11, rapid: true);
                  }
                  _loopEditStart = null;
                },
                onEightRangeChanged: _selectEightRange,
                onRepeatChanged: (value) {
                  if (value != _repeat) {
                    EasterEggService.instance.count('repeat', 11);
                  }
                  setState(() => _repeat = value);
                },
                onSeekToLoopStart: () => _player?.seekTo(_loop.start),
                onRestChanged: (value) => setState(() => _rest = value),
                onMarkEight: _markEightBoundary,
                onResetEight: () => setState(() {
                  _firstEightStart = null;
                  _grid = null;
                  _loopStartEight = 1;
                  _loopEndEight = 1;
                }),
                onOutputChanged: (value) =>
                    setState(() => _recordingOutput = value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _LearningCanvas extends StatelessWidget {
  const _LearningCanvas({
    required this.player,
    required this.mirrorA,
    required this.showCameraB,
    required this.recording,
    required this.onRecordingChanged,
  });

  final VideoPlayerController player;
  final bool mirrorA;
  final bool showCameraB;
  final bool recording;
  final ValueChanged<XFile?> onRecordingChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final reference = ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: player.value.aspectRatio,
            child: Transform.flip(flipX: mirrorA, child: VideoPlayer(player)),
          ),
        ),
      );
      final camera = FrontCameraPanel(
        recording: recording,
        onRecordingChanged: onRecordingChanged,
      );
      final landscape = constraints.maxWidth > constraints.maxHeight;
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: !showCameraB
            ? reference
            : landscape
            ? Row(
                children: [
                  Expanded(flex: 2, child: reference),
                  const VerticalDivider(width: 3, thickness: 3),
                  Expanded(child: camera),
                ],
              )
            : Column(
                children: [
                  Expanded(flex: 3, child: reference),
                  const Divider(height: 3, thickness: 3),
                  Expanded(flex: 2, child: camera),
                ],
              ),
      );
    },
  );
}

final class _RestCountdownOverlay extends StatelessWidget {
  const _RestCountdownOverlay({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Semantics(
      liveRegion: true,
      label: '休息，剩餘 $seconds 秒',
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.68),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.self_improvement, size: 44, color: Colors.white),
              const SizedBox(height: 8),
              Text(
                '休息',
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: Colors.white),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Text(
                  '$seconds',
                  key: ValueKey(seconds),
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Text('下一輪即將開始', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _BottomLearningSettings extends StatelessWidget {
  const _BottomLearningSettings({
    required this.expanded,
    required this.onToggle,
    required this.projectControls,
    required this.child,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Widget projectControls;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          child: SizedBox(
            height: 38,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.tune, size: 18),
                      const SizedBox(width: 7),
                      const Flexible(child: Text('練習・循環・八拍設定')),
                      const SizedBox(width: 7),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        size: 18,
                      ),
                    ],
                  ),
                ),
                projectControls,
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.bottomCenter,
          child: expanded
              ? SizedBox(
                  height: (MediaQuery.sizeOf(context).height * 0.34).clamp(
                    120.0,
                    310.0,
                  ),
                  child: child,
                )
              : const SizedBox.shrink(),
        ),
      ],
    ),
  );
}

final class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.duration,
    required this.loop,
    required this.rate,
    required this.repeat,
    required this.rest,
    required this.firstEightStart,
    required this.grid,
    required this.loopStartEight,
    required this.loopEndEight,
    required this.recordingOutput,
    required this.onPickVideo,
    required this.onRateChanged,
    required this.onLoopChanged,
    required this.onLoopChangeStart,
    required this.onLoopChangeEnd,
    required this.onEightRangeChanged,
    required this.onRepeatChanged,
    required this.onSeekToLoopStart,
    required this.onRestChanged,
    required this.onMarkEight,
    required this.onResetEight,
    required this.onOutputChanged,
  });

  final Duration duration;
  final TimeRange loop;
  final PlaybackRate rate;
  final bool repeat;
  final Duration rest;
  final Duration? firstEightStart;
  final EightCountGrid? grid;
  final int loopStartEight;
  final int loopEndEight;
  final RecordingOutput recordingOutput;
  final VoidCallback onPickVideo;
  final ValueChanged<PlaybackRate> onRateChanged;
  final ValueChanged<RangeValues> onLoopChanged;
  final ValueChanged<RangeValues> onLoopChangeStart;
  final ValueChanged<RangeValues> onLoopChangeEnd;
  final void Function(int startEight, int endEight) onEightRangeChanged;
  final ValueChanged<bool> onRepeatChanged;
  final VoidCallback onSeekToLoopStart;
  final ValueChanged<Duration> onRestChanged;
  final VoidCallback onMarkEight;
  final VoidCallback onResetEight;
  final ValueChanged<RecordingOutput> onOutputChanged;

  @override
  Widget build(BuildContext context) {
    final eightGrid = grid;
    final maximumEight = eightGrid?.availableEightCount(duration) ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('練習設定', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(onPressed: onPickVideo, child: const Text('更換影片')),
            ],
          ),
          PlaybackRateControl(value: rate, onChanged: onRateChanged),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('重複循環'),
                  value: repeat,
                  onChanged: onRepeatChanged,
                ),
              ),
              IconButton.filledTonal(
                tooltip: '回到循環開頭',
                onPressed: onSeekToLoopStart,
                icon: const Icon(Icons.skip_previous),
              ),
            ],
          ),
          if (eightGrid != null && maximumEight > 0) ...[
            Text('用八拍快速定位', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            _EightRangeLocator(
              startEight: loopStartEight,
              endEight: loopEndEight,
              maximum: maximumEight,
              onChanged: onEightRangeChanged,
            ),
            const SizedBox(height: 4),
            Text(
              '選擇後會更新下方時間軸；時間軸仍可拖曳細調。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
          ],
          Text(
            '循環 ${formatDuration(loop.start)} – ${formatDuration(loop.end)}',
          ),
          RangeSlider(
            values: RangeValues(
              loop.start.inMilliseconds.toDouble(),
              loop.end.inMilliseconds.toDouble(),
            ),
            max: duration.inMilliseconds
                .toDouble()
                .clamp(1, double.infinity)
                .toDouble(),
            labels: RangeLabels(
              formatDuration(loop.start),
              formatDuration(loop.end),
            ),
            onChanged: onLoopChanged,
            onChangeStart: onLoopChangeStart,
            onChangeEnd: onLoopChangeEnd,
          ),
          Text('每輪休息 ${rest.inSeconds} 秒'),
          Slider(
            value: rest.inSeconds.toDouble(),
            max: 30,
            divisions: 30,
            label: '${rest.inSeconds} 秒',
            onChanged: (value) =>
                onRestChanged(Duration(seconds: value.round())),
          ),
          const Divider(),
          Text('校正八拍', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            firstEightStart == null
                ? '將影片停在第一個「1」拍並標記起點。'
                : grid == null
                ? '起點 ${formatDuration(firstEightStart!)}；停在下一個「1」拍並標記終點。'
                : '每拍 ${grid!.beatLength.inMilliseconds} ms',
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: onMarkEight,
                icon: const Icon(Icons.flag_outlined),
                label: Text(firstEightStart == null ? '標記起點' : '標記終點'),
              ),
              TextButton(onPressed: onResetEight, child: const Text('重設')),
            ],
          ),
          const Divider(),
          DropdownButtonFormField<RecordingOutput>(
            initialValue: recordingOutput,
            decoration: const InputDecoration(labelText: '錄影輸出'),
            items: RecordingOutput.values
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text(value.label)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) onOutputChanged(value);
            },
          ),
        ],
      ),
    );
  }
}

final class _EightRangeLocator extends StatelessWidget {
  const _EightRangeLocator({
    required this.startEight,
    required this.endEight,
    required this.maximum,
    required this.onChanged,
  });

  final int startEight;
  final int endEight;
  final int maximum;
  final void Function(int startEight, int endEight) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _EightStepper(
            label: '從',
            value: startEight,
            canDecrease: startEight > 1,
            canIncrease: startEight < maximum,
            onDecrease: () => onChanged(startEight - 1, endEight),
            onIncrease: () {
              final next = startEight + 1;
              onChanged(next, endEight < next ? next : endEight);
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('到'),
        ),
        Expanded(
          child: _EightStepper(
            label: '到',
            value: endEight,
            canDecrease: endEight > startEight,
            canIncrease: endEight < maximum,
            onDecrease: () => onChanged(startEight, endEight - 1),
            onIncrease: () => onChanged(startEight, endEight + 1),
          ),
        ),
      ],
    );
  }
}

final class _EightStepper extends StatelessWidget {
  const _EightStepper({
    required this.label,
    required this.value,
    required this.canDecrease,
    required this.canIncrease,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final int value;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '上一個八',
            onPressed: canDecrease ? onDecrease : null,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Text(
              '第 $value 個八',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.fade,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '下一個八',
            onPressed: canIncrease ? onIncrease : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

final class _EmptyLearningState extends StatelessWidget {
  const _EmptyLearningState({
    required this.onPickVideo,
    required this.onOpenProjects,
  });

  final VoidCallback onPickVideo;
  final VoidCallback onOpenProjects;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_library_outlined, size: 72),
          const SizedBox(height: 16),
          Text('選一支舞蹈影片開始練習', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('影片與前鏡頭會同時顯示，方便即時核對動作。'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onPickVideo,
            icon: const Icon(Icons.add),
            label: const Text('選擇影片'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onOpenProjects,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('開啟已儲存練習'),
          ),
        ],
      ),
    ),
  );
}
