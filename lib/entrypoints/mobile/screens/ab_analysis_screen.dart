import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/ab_analysis/analysis_exporter.dart';
import '../../../core/ab_analysis/analysis_gallery.dart';
import '../../../core/ab_analysis/analysis_project.dart';
import '../../../core/saved_projects/saved_project.dart';
import '../../../core/shared_video_playback/playback_rate.dart';
import '../../../core/shared_video_playback/time_range.dart';
import '../../../core/shared_video_playback/video_source.dart';
import '../../../infrastructure/analysis/ffmpeg_analysis_exporter.dart';
import '../../../infrastructure/analysis/device_analysis_gallery.dart';
import '../../../infrastructure/media/local_video_picker.dart';
import '../../../infrastructure/saved_projects/local_saved_project_store.dart';
import '../../../infrastructure/saved_projects/project_media_store.dart';
import '../../../infrastructure/video_playback/latest_video_seeker.dart';
import '../../../infrastructure/video_playback/local_video_controller.dart';
import '../widgets/playback_rate_control.dart';
import '../widgets/precision_scrub_slider.dart';
import '../widgets/saved_project_controls.dart';
import '../widgets/time_text.dart';

final class AbAnalysisScreen extends StatefulWidget {
  const AbAnalysisScreen({super.key});

  @override
  State<AbAnalysisScreen> createState() => _AbAnalysisScreenState();
}

enum _ComparisonLayout { vertical, horizontal }

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

  AnalysisTrack toDomain() => AnalysisTrack(
    source: source,
    mediaDuration: player.value.duration,
    trim: trim,
    rate: rate,
  );
}

final class _AbAnalysisScreenState extends State<AbAnalysisScreen> {
  static const _picker = LocalVideoPicker();
  static const _exporter = FfmpegAnalysisExporter();
  static const _gallery = DeviceAnalysisGallery();
  static final _projectStore = LocalSavedProjectStore.instance;
  static const _projectMediaStore = ProjectMediaStore();

  _TrackState? _trackA;
  _TrackState? _trackB;
  double _progress = 0;
  bool _commonPlaying = false;
  bool _endingCommonPlayback = false;
  bool _orientationLocked = false;
  bool _exporting = false;
  bool _mirrorA = false;
  bool _mirrorB = false;
  _ComparisonLayout _layout = _ComparisonLayout.vertical;
  AnalysisOutput _output = AnalysisOutput.sideBySide;
  AnalysisGalleryFolder _exportFolder = AnalysisGalleryFolder.defaultFolder;
  String? _savedProjectId;
  String? _savedProjectName;

  Duration get _sharedDuration {
    final a = _trackA;
    final b = _trackB;
    if (a != null && b != null) {
      return AnalysisProject(
        trackA: a.toDomain(),
        trackB: b.toDomain(),
        output: _output,
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
    final state = _TrackState(
      source: source,
      player: player,
      seeker: LatestVideoSeeker(player),
      trim: TimeRange(start: Duration.zero, end: player.value.duration),
      rate: PlaybackRate(1),
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
  }

  void _onTrackTick(VideoPlayerController player, bool isA) {
    if (!mounted) return;
    final track = isA ? _trackA : _trackB;
    if (track == null || !identical(track.player, player)) return;

    if (_commonPlaying) {
      if (player.value.position >= _commonSourceEnd(track)) {
        _finishCommonPlayback();
        return;
      }
      if ((isA || _trackA == null) && _sharedDuration > Duration.zero) {
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
    await Future.wait(
      [
        _trackA?.player,
        _trackB?.player,
      ].whereType<VideoPlayerController>().map((player) => player.pause()),
    );
    if (mounted) {
      setState(() {
        _progress = 1;
        _commonPlaying = false;
      });
    }
    _endingCommonPlayback = false;
  }

  Duration _sourcePosition(_TrackState track, double progress) {
    final a = _trackA;
    final b = _trackB;
    if (a != null && b != null) {
      final project = AnalysisProject(
        trackA: a.toDomain(),
        trackB: b.toDomain(),
        output: _output,
      );
      return project.sourcePositionAt(track.toDomain(), progress);
    }
    return track.trim.clamp(track.trim.start + track.trim.duration * progress);
  }

  Future<void> _seekBoth(double progress) async {
    final a = _trackA;
    final b = _trackB;
    final aPosition = a == null ? null : _sourcePosition(a, progress);
    final bPosition = b == null ? null : _sourcePosition(b, progress);
    setState(() => _progress = progress);
    final operations = <Future<void>>[];
    if (a != null) {
      operations.add(a.seeker.seek(aPosition!));
    }
    if (b != null) {
      operations.add(b.seeker.seek(bPosition!));
    }
    await Future.wait(operations);
  }

  Future<void> _beginCommonSeek(double _) async {
    _commonPlaying = false;
    await Future.wait(
      [
        _trackA?.player,
        _trackB?.player,
      ].whereType<VideoPlayerController>().map((player) => player.pause()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleCommonPlayback() async {
    final tracks = [_trackA, _trackB].whereType<_TrackState>().toList();
    if (tracks.isEmpty) return;
    if (_commonPlaying) {
      await Future.wait(tracks.map((track) => track.player.pause()));
      if (mounted) setState(() => _commonPlaying = false);
      return;
    }
    await Future.wait(tracks.map((track) => track.player.pause()));
    if (_progress >= 0.999) await _seekBoth(0);
    await Future.wait(
      tracks.map(
        (track) => track.seeker.seek(_sourcePosition(track, _progress)),
      ),
    );
    await Future.wait(tracks.map((track) => track.player.play()));
    // Some Android devices briefly yield audio focus while the second native
    // player starts. With mixing enabled, retry any controller that did not
    // remain playing so A and B enter the shared session together.
    final stoppedTracks = tracks.where(
      (track) => !track.player.value.isPlaying,
    );
    await Future.wait(stoppedTracks.map((track) => track.player.play()));
    if (mounted) setState(() => _commonPlaying = true);
  }

  Future<void> _toggleTrack(bool isA) async {
    final track = isA ? _trackA : _trackB;
    if (track == null) return;
    if (_commonPlaying) {
      await Future.wait(
        [
          _trackA?.player,
          _trackB?.player,
        ].whereType<VideoPlayerController>().map((player) => player.pause()),
      );
      _commonPlaying = false;
    }
    if (track.player.value.isPlaying) {
      await track.player.pause();
    } else {
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
    if (mounted) {
      setState(() {
        _progress = 0;
        _commonPlaying = false;
      });
    }
    await track.seeker.seek(startMoved ? start : end);
  }

  Future<void> _changeRate(bool isA, PlaybackRate rate) async {
    final track = isA ? _trackA : _trackB;
    if (track == null) return;
    track.rate = rate;
    await track.player.setPlaybackSpeed(rate.value);
    if (mounted) setState(() => _progress = 0);
  }

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
    _TrackState track,
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

  Future<void> _saveProject() async {
    if (_trackA == null && _trackB == null) return;
    var name = _savedProjectName;
    if (_savedProjectId == null) {
      final labels = [
        _trackA?.source.label,
        _trackB?.source.label,
      ].whereType<String>().join(' + ');
      name = await requestProjectName(context, initialValue: labels);
      if (name == null || !mounted) return;
    }
    try {
      final savedA = _trackA == null
          ? null
          : await _projectMediaStore.persistVideo(_trackA!.source);
      final savedB = _trackB == null
          ? null
          : await _projectMediaStore.persistVideo(_trackB!.source);
      final project = await _projectStore.save(
        id: _savedProjectId,
        name: name!,
        mode: SavedProjectMode.analysis,
        data: {
          'trackA': _trackA == null
              ? null
              : _trackProjectData(_trackA!, savedA!),
          'trackB': _trackB == null
              ? null
              : _trackProjectData(_trackB!, savedB!),
          'progress': _progress,
          'mirrorA': _mirrorA,
          'mirrorB': _mirrorB,
          'layout': _layout.name,
          'output': _output.name,
          'exportFolder': _exportFolder.path,
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
    final rate = PlaybackRate((data['rate'] as num).toDouble());
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
      final folder = AnalysisGalleryFolder.tryParse(
        (data['exportFolder'] as String?) ?? '',
      );
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
        _exportFolder = folder ?? AnalysisGalleryFolder.defaultFolder;
        _orientationLocked = false;
        _savedProjectId = project.id;
        _savedProjectName = project.name;
      });
      nextA?.player.addListener(() => _onTrackTick(nextA!.player, true));
      nextB?.player.addListener(() => _onTrackTick(nextB!.player, false));
      await SystemChrome.setPreferredOrientations([]);
      await _seekBoth(_progress);
      oldA?.seeker.dispose();
      oldB?.seeker.dispose();
      await oldA?.player.dispose();
      await oldB?.player.dispose();
      _showProjectMessage('已開啟「${project.name}」');
    } catch (error) {
      await nextA?.player.dispose();
      await nextB?.player.dispose();
      if (mounted) _showProjectMessage('無法開啟專案，請確認 A、B 原始影片仍存在。');
    }
  }

  void _showProjectMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _export() async {
    final a = _trackA;
    final b = _trackB;
    if (a == null || b == null) return;
    setState(() => _exporting = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在輸出影片，請保持 Terpsichore 開啟…'),
        duration: Duration(seconds: 3),
      ),
    );
    try {
      final project = AnalysisProject(
        trackA: a.toDomain(),
        trackB: b.toDomain(),
        output: _output,
      );
      final result = await _exporter.export(AnalysisExportRequest(project));
      if (!mounted) return;
      final message = switch (result) {
        AnalysisExported() => '影片已保存在 Terpsichore 本機資料夾。',
        AnalysisExportUnsupported(:final reason) => reason,
        AnalysisExportFailed(:final reason) => reason,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      if (result case AnalysisExported(:final path)) {
        final galleryResult = await _gallery.save(path, folder: _exportFolder);
        if (!mounted) return;
        if (galleryResult case AnalysisGallerySaveFailed(:final reason)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('影片已輸出，但無法加入媒體瀏覽器：$reason')));
          return;
        }
        final shouldShare = await _askExportDestination(path, _exportFolder);
        if (shouldShare && mounted) await _shareExport(path);
      }
    } finally {
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
        : '${folder.path} 相簿';
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('影片已加入媒體瀏覽器'),
            content: Text('$fileName\n\n已儲存到 $savedLocation。現在要選擇傳送目的地嗎？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('留在媒體庫'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.send_outlined),
                label: const Text('選擇目的地'),
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
        text: 'Terpsichore 分析影片',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  void dispose() {
    _trackA?.seeker.dispose();
    _trackB?.seeker.dispose();
    _trackA?.player.dispose();
    _trackB?.player.dispose();
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
        title: 'A・參考影片',
        track: _trackA,
        onPick: () => _pick(true),
        onTogglePlay: () => _toggleTrack(true),
        onTrimChanged: (values) => _changeTrim(true, values),
        onRateChanged: (rate) => _changeRate(true, rate),
        mirrored: _mirrorA,
        onToggleMirror: () => setState(() => _mirrorA = !_mirrorA),
        verticalControls: effectiveLayout == _ComparisonLayout.vertical,
      ),
      _TrackCard(
        title: 'B・我的影片',
        track: _trackB,
        onPick: () => _pick(false),
        onTogglePlay: () => _toggleTrack(false),
        onTrimChanged: (values) => _changeTrim(false, values),
        onRateChanged: (rate) => _changeRate(false, rate),
        mirrored: _mirrorB,
        onToggleMirror: () => setState(() => _mirrorB = !_mirrorB),
        verticalControls: effectiveLayout == _ComparisonLayout.vertical,
      ),
    ];

    return SafeArea(
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
                onSave: _saveProject,
                onLoad: _loadProject,
              ),
              onOpenExportSettings: _showExportSettings,
              onExport: _export,
            ),
            const SizedBox(height: 4),
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
              playing: _commonPlaying,
              progress: _progress,
              duration: _sharedDuration,
              enabled: _trackA != null || _trackB != null,
              onToggle: _toggleCommonPlayback,
              onSeekStart: _beginCommonSeek,
              onSeek: _seekBoth,
            ),
          ],
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
  Widget build(BuildContext context) => Row(
    children: [
      SegmentedButton<_ComparisonLayout>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: _ComparisonLayout.vertical,
            icon: Icon(Icons.view_agenda_outlined, size: 18),
            tooltip: '上下排列（直版）',
          ),
          ButtonSegment(
            value: _ComparisonLayout.horizontal,
            icon: Icon(Icons.view_column_outlined, size: 18),
            tooltip: '左右排列（橫版）',
          ),
        ],
        selected: {layout},
        onSelectionChanged: (value) => onLayoutChanged(value.first),
      ),
      IconButton(
        tooltip: orientationLocked ? '解除畫面鎖定' : '鎖定目前版面方向',
        onPressed: onToggleLock,
        icon: Icon(
          orientationLocked
              ? Icons.screen_lock_rotation
              : Icons.screen_rotation_outlined,
        ),
      ),
      const Spacer(),
      projectControls,
      IconButton(
        tooltip: '輸出設定：Movies/${exportFolder.path}',
        onPressed: onOpenExportSettings,
        icon: const Icon(Icons.tune),
      ),
      IconButton.filledTonal(
        tooltip: '輸出並儲存分析影片',
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
      ).showSnackBar(const SnackBar(content: Text('請輸入有效的資料夾名稱')));
      return;
    }
    Navigator.pop(context, _ExportSettings(output: _output, folder: folder));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('輸出設定'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<AnalysisOutput>(
          initialValue: _output,
          decoration: const InputDecoration(labelText: '影片內容'),
          items: const [
            DropdownMenuItem(
              value: AnalysisOutput.sideBySide,
              child: Text('輸出 A+B'),
            ),
            DropdownMenuItem(
              value: AnalysisOutput.trackBOnly,
              child: Text('只輸出 B'),
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
            labelText: Platform.isAndroid ? '輸出資料夾' : '輸出相簿',
            prefixText: Platform.isAndroid ? 'Movies/' : null,
            helperText: '可輸入子資料夾，例如 Terpsichore/A+B',
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('套用')),
    ],
  );
}

final class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.title,
    required this.track,
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
  final VoidCallback onPick;
  final VoidCallback onTogglePlay;
  final ValueChanged<RangeValues> onTrimChanged;
  final ValueChanged<PlaybackRate> onRateChanged;
  final bool mirrored;
  final VoidCallback onToggleMirror;
  final bool verticalControls;

  @override
  Widget build(BuildContext context) {
    final value = track;
    final video = ColoredBox(
      color: Colors.black,
      child: value == null
          ? Center(
              child: FilledButton.tonalIcon(
                onPressed: onPick,
                icon: const Icon(Icons.add_to_photos_outlined),
                label: const Text('選擇影片'),
              ),
            )
          : Center(
              child: AspectRatio(
                aspectRatio: value.player.value.aspectRatio,
                child: Transform.flip(
                  flipX: mirrored,
                  child: VideoPlayer(value.player),
                ),
              ),
            ),
    );
    final trimSlider = value == null
        ? null
        : RangeSlider(
            values: RangeValues(
              value.trim.start.inMilliseconds.toDouble(),
              value.trim.end.inMilliseconds.toDouble(),
            ),
            max: value.player.value.duration.inMilliseconds
                .toDouble()
                .clamp(1, double.infinity)
                .toDouble(),
            onChanged: onTrimChanged,
          );
    final controls = value == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (verticalControls)
                  Row(
                    children: [
                      _TrackPlayButton(
                        title: title,
                        playing: value.player.value.isPlaying,
                        onPressed: onTogglePlay,
                      ),
                      Expanded(
                        child: PlaybackRateControl(
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
                    value: value.rate,
                    onChanged: onRateChanged,
                    showSlider: false,
                  ),
                ],
                if (verticalControls) trimSlider!,
                if (verticalControls) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('起點  ${formatDuration(value.trim.start)}'),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('終點  ${formatDuration(value.trim.end)}'),
                  ),
                ] else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('起 ${formatDuration(value.trim.start)}'),
                      Text('終 ${formatDuration(value.trim.end)}'),
                    ],
                  ),
                Text(
                  '來源 ${_formatDuration(value.trim.duration)}  ·  '
                  '${value.rate.value.toStringAsFixed(2)}x 後 '
                  '${_formatDuration(value.toDomain().effectiveDuration)}',
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
                    tooltip: mirrored ? '取消鏡像' : '開啟鏡像',
                    onPressed: onToggleMirror,
                    isSelected: mirrored,
                    icon: const Icon(Icons.flip),
                  ),
                TextButton(
                  onPressed: onPick,
                  child: Text(value == null ? '選擇' : '更換'),
                ),
              ],
            ),
          ),
          Expanded(
            child: controls == null
                ? video
                : verticalControls
                ? Column(
                    children: [
                      Expanded(child: video),
                      controls,
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
    tooltip: '$title 單獨播放',
    onPressed: onPressed,
    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
  );
}

final class _CommonTimeline extends StatelessWidget {
  const _CommonTimeline({
    required this.playing,
    required this.progress,
    required this.duration,
    required this.enabled,
    required this.onToggle,
    required this.onSeekStart,
    required this.onSeek,
  });

  final bool playing;
  final double progress;
  final Duration duration;
  final bool enabled;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton.filled(
        tooltip: '共同播放',
        onPressed: enabled ? onToggle : null,
        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
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
              ? (position) =>
                    onSeek(position.inMicroseconds / duration.inMicroseconds)
              : (_) {},
          onChangeEnd: enabled
              ? (position) =>
                    onSeek(position.inMicroseconds / duration.inMicroseconds)
              : null,
        ),
      ),
      Text(
        '${_formatDuration(duration * progress)} / ${_formatDuration(duration)}',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    ],
  );
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  final tenths = duration.inMilliseconds.remainder(1000) ~/ 100;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
}
