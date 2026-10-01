import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/ab_analysis/analysis_gallery.dart';
import '../../../core/ab_analysis/pose_3d.dart';
import '../../../infrastructure/analysis/pose_3d_analyzer.dart';
import '../../../infrastructure/analysis/pose_3d_job.dart';
import '../../../infrastructure/analysis/pose_3d_exporter.dart';
import '../../../infrastructure/analysis/device_analysis_gallery.dart';
import '../../../infrastructure/video_playback/latest_video_seeker.dart';
import '../localization/app_text.dart';
import '../widgets/pose_3d_view.dart';
import '../widgets/pose_3d_progress.dart';

final class Pose3dScreen extends StatefulWidget {
  const Pose3dScreen({super.key, required this.job, required this.folder});
  final Pose3dJob job;
  final AnalysisGalleryFolder folder;
  @override
  State<Pose3dScreen> createState() => _Pose3dScreenState();
}

final class _Pose3dScreenState extends State<Pose3dScreen>
    with WidgetsBindingObserver {
  Pose3dComparison? get _data => widget.job.result;
  bool _playersStarted = false;
  double _seconds = 0, _zoom = 1, _startZoom = 1;
  Pose3dRotation _rotation = Pose3dRotation.view();
  Offset? _lastDrag;
  int _dragPointers = 0;
  bool _video = false, _playing = false, _videoReady = false;
  Timer? _timer;
  final _clock = Stopwatch();
  double _anchor = 0;
  final _players = <VideoPlayerController>[];
  final _seekers = <LatestVideoSeeker>[];
  int _playRequest = 0;
  Pose3dExporter? _exporter;
  Pose3dRenderer? _renderer;
  double _exportProgress = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.job.addListener(_onJob);
    _onJob();
    unawaited(_loadRenderer());
  }

  Future<void> _loadRenderer() async {
    try {
      final renderer = await Pose3dRenderer.load();
      if (!mounted) {
        renderer.dispose();
        return;
      }
      setState(() => _renderer = renderer);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appText(context, '立體顯示載入失敗，暫用簡化骨架。'))),
      );
    }
  }

  void _onJob() {
    if (!mounted) return;
    setState(() {});
    if (_data != null && !_playersStarted) {
      _playersStarted = true;
      unawaited(_initPlayers());
    }
  }

  Future<void> _initPlayers() async {
    try {
      for (final t in [widget.job.project.trackA, widget.job.project.trackB]) {
        final c = VideoPlayerController.file(File(t.source.path));
        _players.add(c);
        _seekers.add(LatestVideoSeeker(c));
        await c.initialize();
        if (!mounted) return;
        await c.setVolume(0);
        await c.setPlaybackSpeed(t.rate.value);
        await c.seekTo(t.trim.start);
      }
      if (mounted) setState(() => _videoReady = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appError(context, e))));
      }
    }
  }

  Pose3dCamera get _camera =>
      Pose3dCamera.oriented(rotation: _rotation, zoom: _zoom);

  Future<void> _settings() async {
    var fps = widget.job.settings.fps;
    var interpolate = widget.job.settings.interpolate;
    final value = await showDialog<Pose3dSettings>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(appText(context, '3D Pose 設定')),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('NLF-L INT8'),
              DropdownButtonFormField<int>(
                key: const ValueKey('pose3d-page-fps'),
                initialValue: fps,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: appText(context, '3D 推論 FPS'),
                ),
                items: [
                  for (final n in Pose3dSettings.fpsOptions)
                    DropdownMenuItem(value: n, child: Text('$n FPS')),
                ],
                onChanged: (v) {
                  if (v != null) update(() => fps = v);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(appText(context, 'Post-processing：內插其餘影格')),
                subtitle: Text(
                  appText(context, '內插播放與輸出影格；短暫漏偵測最多補 2 個採樣點，前後間隔須在 0.6 秒內。'),
                ),
                value: interpolate,
                onChanged: (v) => update(() => interpolate = v),
              ),
              Text(appText(context, '設定只套用到下一次推論；按重新推論後才會更新結果。')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(appText(context, '取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                Pose3dSettings(fps: fps, interpolate: interpolate),
              ),
              child: Text(appText(context, '儲存')),
            ),
          ],
        ),
      ),
    );
    if (value == null || !mounted) return;
    widget.job.updateSettings(value);
    try {
      final file = File(
        '${(await getApplicationSupportDirectory()).path}/pose_settings.json',
      );
      final data = await file.exists()
          ? Map<String, dynamic>.from(
              jsonDecode(await file.readAsString()) as Map,
            )
          : <String, dynamic>{};
      data['pose3d'] = value.toJson();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appError(context, e))));
      }
    }
  }

  void _pause() {
    _playRequest++;
    _timer?.cancel();
    _clock.stop();
    _playing = false;
    for (final c in _players) {
      unawaited(c.pause());
    }
  }

  Future<void> _seek(double t) async {
    if (_data == null) return;
    _pause();
    setState(() => _seconds = t);
    await _syncPlayers(t);
  }

  Future<void> _syncPlayers(double t) async {
    if (!_videoReady || _data == null) return;
    try {
      await Future.wait([
        for (var i = 0; i < 2; i++)
          _seekers[i].seek(
            widget.job.project.sourcePositionAt(
              i == 0 ? widget.job.project.trackA : widget.job.project.trackB,
              t / _data!.seconds,
            ),
          ),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appError(context, e))));
      }
    }
  }

  Future<void> _play() async {
    if (_playing) {
      setState(_pause);
      return;
    }
    if (_data == null) return;
    if (_seconds >= _data!.seconds - .01) await _seek(0);
    final request = ++_playRequest;
    if (_video && _videoReady) {
      await _syncPlayers(_seconds);
      if (!mounted || request != _playRequest) return;
      await Future.wait(_players.map((p) => p.play()));
    }
    if (!mounted || request != _playRequest) return;
    _anchor = _seconds;
    _clock
      ..reset()
      ..start();
    setState(() => _playing = true);
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted) return;
      setState(() {
        _seconds = (_anchor + _clock.elapsedMicroseconds / 1e6).clamp(
          0.0,
          _data!.seconds,
        );
        if (_seconds >= _data!.seconds) _pause();
      });
    });
  }

  Future<void> _save() async {
    if (_data == null || _exporter != null) return;
    _pause();
    final exporter = Pose3dExporter();
    final camera = _camera;
    setState(() {
      _exporter = exporter;
      _exportProgress = 0;
    });
    File? file;
    try {
      file = await exporter.export(_data!, camera, (p) {
        if (mounted) setState(() => _exportProgress = p);
      });
      if (!mounted || exporter.cancelled) return;
      final result = await const DeviceAnalysisGallery().save(
        file.path,
        folder: widget.folder,
      );
      if (result is AnalysisGallerySaveFailed) throw StateError(result.reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appText(context, '3D 影片已儲存至相簿'))),
        );
      }
    } on Pose3dCancelled {
      /* Explicit cancellation does not save a partial file. */
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appError(context, e))));
      }
    } finally {
      if (file != null && await file.exists()) await file.delete();
      if (mounted) setState(() => _exporter = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) setState(_pause);
  }

  @override
  void dispose() {
    _renderer?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.job.removeListener(_onJob);
    unawaited(_exporter?.cancel());
    _pause();
    for (final seeker in _seekers) {
      seeker.dispose();
    }
    for (final c in _players) {
      unawaited(c.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final job = widget.job;
    final error = job.error != null
        ? appError(context, job.error!)
        : job.status == Pose3dJobStatus.cancelled
        ? appText(context, '分析已取消')
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context, '3D Pose')),
        actions: [
          IconButton(
            tooltip: appText(context, '儲存 3D 影片'),
            onPressed: data != null && _exporter == null ? _save : null,
            icon: const Icon(Icons.save_alt),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  key: const ValueKey('pose3d-rerun'),
                  onPressed: job.busy || _exporter != null
                      ? null
                      : () {
                          _pause();
                          job.start();
                        },
                  icon: const Icon(Icons.refresh),
                  label: Text(appText(context, '重新推論')),
                ),
                TextButton.icon(
                  key: const ValueKey('pose3d-settings'),
                  onPressed: _exporter != null ? null : _settings,
                  icon: const Icon(Icons.tune),
                  label: Text(appText(context, '3D Pose 設定')),
                ),
                if (job.busy)
                  TextButton(
                    key: const ValueKey('pose3d-cancel'),
                    onPressed: job.status == Pose3dJobStatus.cancelling
                        ? null
                        : job.cancel,
                    child: Text(
                      appText(
                        context,
                        job.status == Pose3dJobStatus.cancelling
                            ? '正在取消分析…'
                            : '取消分析',
                      ),
                    ),
                  ),
              ],
            ),
            if (data != null)
              Text(
                appText(context, '已完成：{0} FPS；下次推論：{1} FPS', [
                  data.settings.fps,
                  job.settings.fps,
                ]),
              ),
            if (data != null && job.busy) ...[
              LinearProgressIndicator(value: job.progress),
              Pose3dProgress(job: job),
            ],
            if (data != null && error != null) Text(error),
            if (job.cacheError != null)
              Text(appText(context, '結果保留於本次使用，無法儲存快取。')),
            Expanded(
              child: error != null && data == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(error),
                      ),
                    )
                  : data == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 220,
                            child: LinearProgressIndicator(value: job.progress),
                          ),
                          const SizedBox(height: 16),
                          Pose3dProgress(job: job),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              appText(context, '返回上一頁會繼續分析，可再按 3D Pose 查看進度。'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: SegmentedButton<bool>(
                            segments: [
                              ButtonSegment(
                                value: false,
                                label: Text(appText(context, '3D 骨架')),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text(appText(context, '原影片')),
                                enabled: _videoReady,
                              ),
                            ],
                            selected: {_video},
                            onSelectionChanged: _exporter != null
                                ? null
                                : (v) {
                                    unawaited(_seek(_seconds));
                                    setState(() => _video = v.first);
                                  },
                          ),
                        ),
                        Expanded(
                          child: _video && _videoReady
                              ? Row(
                                  children: [
                                    for (final p in _players)
                                      Expanded(
                                        child: Center(
                                          child: AspectRatio(
                                            aspectRatio: p.value.aspectRatio,
                                            child: VideoPlayer(p),
                                          ),
                                        ),
                                      ),
                                  ],
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) =>
                                      GestureDetector(
                                        onScaleStart: _exporter != null
                                            ? null
                                            : (d) {
                                                _startZoom = _zoom;
                                                _lastDrag = d.localFocalPoint;
                                                _dragPointers = d.pointerCount;
                                              },
                                        onScaleUpdate: _exporter != null
                                            ? null
                                            : (d) => setState(() {
                                                if (d.pointerCount == 1 &&
                                                    _dragPointers == 1 &&
                                                    _lastDrag != null) {
                                                  _rotation =
                                                      Pose3dRotation.drag(
                                                        _lastDrag!,
                                                        d.localFocalPoint,
                                                        constraints.biggest,
                                                      ) *
                                                      _rotation;
                                                }
                                                _lastDrag = d.localFocalPoint;
                                                _dragPointers = d.pointerCount;
                                                _zoom = (_startZoom * d.scale)
                                                    .clamp(.3, 3.0);
                                              }),
                                        child: CustomPaint(
                                          painter: Pose3dPainter(
                                            data.a.at(
                                              _seconds,
                                              interpolate:
                                                  data.settings.interpolate,
                                            ),
                                            data.b.at(
                                              _seconds,
                                              interpolate:
                                                  data.settings.interpolate,
                                            ),
                                            _camera,
                                            renderer: _renderer,
                                          ),
                                          child: const SizedBox.expand(),
                                        ),
                                      ),
                                ),
                        ),
                        if (!_video)
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              for (final preset in [
                                ('正面', 0.0, 0.0),
                                ('側面', math.pi / 2, 0.0),
                                ('俯瞰', 0.0, math.pi / 2),
                              ])
                                TextButton(
                                  key: ValueKey('pose3d-view-${preset.$1}'),
                                  onPressed: _exporter != null
                                      ? null
                                      : () => setState(() {
                                          _rotation = Pose3dRotation.view(
                                            yaw: preset.$2,
                                            pitch: preset.$3,
                                          );
                                        }),
                                  child: Text(appText(context, preset.$1)),
                                ),
                              TextButton(
                                key: const ValueKey('pose3d-reset-camera'),
                                onPressed: _exporter != null
                                    ? null
                                    : () => setState(() {
                                        _rotation = Pose3dRotation.view();
                                        _zoom = 1;
                                      }),
                                child: Text(appText(context, '重設視角')),
                              ),
                            ],
                          ),
                        if (!_video)
                          Text(
                            appText(context, '拖曳旋轉，雙指縮放；儲存使用目前視角'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        Slider(
                          value: _seconds.clamp(0.0, data.seconds),
                          max: data.seconds,
                          onChanged: _exporter != null
                              ? null
                              : (t) => unawaited(_seek(t)),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: _exporter != null ? null : _play,
                              tooltip: appText(context, _playing ? '暫停' : '播放'),
                              icon: Icon(
                                _playing ? Icons.pause : Icons.play_arrow,
                              ),
                            ),
                            Text(
                              '${_seconds.toStringAsFixed(2)} / ${data.seconds.toStringAsFixed(2)} s',
                            ),
                          ],
                        ),
                        if (_exporter != null) ...[
                          LinearProgressIndicator(value: _exportProgress),
                          TextButton(
                            onPressed: () => _exporter?.cancel(),
                            child: Text(appText(context, '取消輸出')),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
