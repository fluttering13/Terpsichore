import 'package:terpsichore/infrastructure/engagement/easter_egg_service.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/music_practice/music_loop_policy.dart';
import '../../../core/music_practice/music_practice_session.dart';
import '../../../core/music_practice/music_practice_source.dart';
import '../../../core/music_practice/music_track_selection.dart';
import '../../../core/music_practice/stem_separation.dart';
import '../../../core/saved_projects/saved_project.dart';
import '../../../core/shared_video_playback/playback_rate.dart';
import '../../../core/shared_video_playback/time_range.dart';
import '../../../infrastructure/music_practice/ffmpeg_music_media_preparer.dart';
import '../../../infrastructure/music_practice/ffmpeg_music_practice_mix_builder.dart';
import '../../../infrastructure/music_practice/htdemucs_onnx_stem_separator.dart';
import '../../../infrastructure/music_practice/local_music_media_picker.dart';
import '../../../infrastructure/music_practice/wav_waveform_analyzer.dart';
import '../../../infrastructure/saved_projects/local_saved_project_store.dart';
import '../widgets/playback_rate_control.dart';
import '../widgets/precision_scrub_slider.dart';
import '../widgets/saved_project_controls.dart';
import '../widgets/time_text.dart';

final class MusicPracticeScreen extends StatefulWidget {
  const MusicPracticeScreen({super.key});

  @override
  State<MusicPracticeScreen> createState() => _MusicPracticeScreenState();
}

final class _MusicPracticeScreenState extends State<MusicPracticeScreen> {
  static const _picker = LocalMusicMediaPicker();
  static const _preparer = FfmpegMusicMediaPreparer();
  static const _separator = HtdemucsOnnxStemSeparator();
  static const _mixBuilder = FfmpegMusicPracticeMixBuilder();
  static const _loopPolicy = MusicLoopPolicy();
  static const _waveformAnalyzer = WavWaveformAnalyzer();
  static final _projectStore = LocalSavedProjectStore.instance;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  MusicPracticeSource? _source;
  PreparedMusic? _prepared;
  SeparatedStems? _separated;
  MusicTrackSelection _selection = MusicTrackSelection.original();
  StemSeparationUpdate? _progress;
  Object? _error;
  bool _busy = false;
  bool _practicing = false;
  bool _settingsOpen = false;
  bool _handlingLoop = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  TimeRange _loop = TimeRange(start: Duration.zero, end: Duration.zero);
  PlaybackRate _rate = PlaybackRate(1);
  bool _repeat = false;
  Duration _rest = Duration.zero;
  int? _restCountdown;
  int _countdownGeneration = 0;
  String? _playbackPath;
  String? _savedProjectId;
  String? _savedProjectName;
  Map<String, List<double>> _waveforms = const {};
  bool _waveformsLoading = false;
  Object? _waveformError;
  int _waveformGeneration = 0;

  @override
  void initState() {
    super.initState();
    _positionSubscription = _player.positionStream.listen(_onPosition);
    _stateSubscription = _player.playerStateStream.listen((_) {
      _sampleEggs();
      if (mounted) setState(() {});
    });
  }

  Future<void> _pickMedia() async {
    final source = await _picker.pick();
    if (source == null) return;
    await _player.pause();
    _countdownGeneration++;
    _waveformGeneration++;
    setState(() {
      _busy = true;
      _error = null;
      _source = source;
      _prepared = null;
      _separated = null;
      _selection = MusicTrackSelection.original();
      _waveforms = const {};
      _waveformError = null;
      _practicing = false;
      _progress = const StemSeparationUpdate(
        stage: StemSeparationStage.preparingAudio,
        progress: 0,
      );
    });
    try {
      final prepared = await _preparer.prepare(
        source,
        onProgress: _setProgress,
      );
      if (!mounted || !identical(source, _source)) return;
      setState(() {
        _prepared = prepared;
        _duration = prepared.duration;
        _loop = TimeRange(start: Duration.zero, end: prepared.duration);
      });
      unawaited(_analyzeWaveforms());
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted && identical(source, _source)) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _splitStems() async {
    final prepared = _prepared;
    if (prepared == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = const StemSeparationUpdate(
        stage: StemSeparationStage.downloadingModel,
        progress: 0,
      );
    });
    try {
      final separated = await _separator.separate(
        prepared,
        onProgress: _setProgress,
      );
      if (!mounted || !identical(prepared, _prepared)) return;
      setState(() => _separated = separated);
      unawaited(_analyzeWaveforms());
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted && identical(prepared, _prepared)) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  void _setProgress(StemSeparationUpdate update) {
    if (mounted) setState(() => _progress = update);
  }

  Future<void> _analyzeWaveforms() async {
    final prepared = _prepared;
    if (prepared == null) return;
    final separated = _separated;
    final paths = separated == null
        ? [prepared.originalWavPath]
        : MusicStem.values.map((stem) => separated.paths[stem]!).toList();
    final generation = ++_waveformGeneration;
    setState(() {
      _waveformsLoading = true;
      _waveformError = null;
    });
    try {
      final waveforms = <String, List<double>>{};
      for (final path in paths) {
        waveforms[path] = await _waveformAnalyzer.analyze(path);
        if (!mounted || generation != _waveformGeneration) return;
      }
      setState(() => _waveforms = waveforms);
    } catch (error) {
      if (mounted && generation == _waveformGeneration) {
        setState(() => _waveformError = error);
      }
    } finally {
      if (mounted && generation == _waveformGeneration) {
        setState(() => _waveformsLoading = false);
      }
    }
  }

  Future<void> _startPractice() async {
    final prepared = _prepared;
    if (prepared == null || !_selection.canPractice || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = _selection.original
          ? prepared.originalWavPath
          : await _mixBuilder.build(
              stems: _separated!,
              selection: _selection.stems,
            );
      await _player.setFilePath(path);
      await _player.setSpeed(_rate.value);
      await _player.seek(Duration.zero);
      if (!mounted || !identical(prepared, _prepared)) return;
      setState(() {
        _countdownGeneration++;
        _practicing = true;
        _restCountdown = null;
        _position = Duration.zero;
        _duration = prepared.duration;
        _loop = TimeRange(start: Duration.zero, end: prepared.duration);
        _playbackPath = path;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sampleEggs() {
    final eggs = EasterEggService.instance;
    if (!eggs.foreground || eggs.page != 3 || eggs.covered) return;
    eggs.engine.segment(
      'music',
      '${_prepared?.originalWavPath}:${_loop.start}:${_loop.end}',
    );
    eggs.engine.practice(
      'music',
      (_player.playing &&
              _player.processingState != ProcessingState.completed) ||
          _handlingLoop ||
          (_repeat && _player.playing && _player.position >= _loop.end),
    );
  }

  void _onPosition(Duration position) {
    _sampleEggs();
    if (!mounted || !_practicing) return;
    if (position != _position) setState(() => _position = position);
    unawaited(_handleLoop(position));
  }

  Future<void> _handleLoop(Duration position) async {
    final prepared = _prepared;
    if (_handlingLoop || prepared == null || _loop.end == Duration.zero) return;
    final decision = _loopPolicy.evaluate(
      MusicPracticeSession(
        playbackPath: prepared.originalWavPath,
        duration: _duration,
        rate: _rate,
        loop: _loop,
        repeatEnabled: _repeat,
        restBetweenLoops: _rest,
      ),
      position,
    );
    if (decision.action == MusicLoopAction.none) return;
    _handlingLoop = true;
    final eggs = EasterEggService.instance;
    if (eggs.foreground && eggs.page == 3 && !eggs.covered && _player.playing) {
      eggs.engine.completedLoop(
        'music',
        '${_prepared?.originalWavPath}:${_loop.start}:${_loop.end}',
      );
    }
    try {
      if (decision.action == MusicLoopAction.pauseThenRestart) {
        await _player.pause();
        final generation = ++_countdownGeneration;
        final stopwatch = Stopwatch()..start();
        while (stopwatch.elapsed < decision.wait) {
          if (!mounted || generation != _countdownGeneration) return;
          final seconds = visibleMusicRestCountdownSeconds(
            decision.wait - stopwatch.elapsed,
          );
          if (_restCountdown != seconds) {
            setState(() => _restCountdown = seconds);
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!mounted || generation != _countdownGeneration) return;
        setState(() => _restCountdown = null);
      }
      await _player.seek(decision.seekTo!);
      await _player.play();
    } finally {
      _handlingLoop = false;
    }
  }

  Future<void> _setRate(PlaybackRate rate) async {
    setState(() => _rate = rate);
    await _player.setSpeed(rate.value);
  }

  Future<void> _setLoop(RangeValues values) async {
    final previous = _loop;
    final next = TimeRange(
      start: Duration(milliseconds: values.start.round()),
      end: Duration(milliseconds: values.end.round()),
    );
    setState(() => _loop = next);
    await _player.seek(next.start != previous.start ? next.start : next.end);
  }

  Future<void> _switchPracticeSelection(MusicTrackSelection next) async {
    final prepared = _prepared;
    final separated = _separated;
    if (prepared == null ||
        _busy ||
        next.original == _selection.original &&
            next.stems.length == _selection.stems.length &&
            next.stems.containsAll(_selection.stems)) {
      return;
    }
    if (!next.canPractice) next = MusicTrackSelection.original();
    if (!next.original && separated == null) return;
    final previous = _selection;
    final wasPlaying = _player.playing;
    final position = _position;
    _countdownGeneration++;
    setState(() {
      _selection = next;
      _busy = true;
      _error = null;
      _restCountdown = null;
    });
    try {
      await _player.pause();
      final path = next.original
          ? prepared.originalWavPath
          : await _mixBuilder.build(stems: separated!, selection: next.stems);
      await _player.setFilePath(path);
      await _player.setSpeed(_rate.value);
      await _player.seek(position);
      if (wasPlaying) await _player.play();
      if (!mounted) return;
      setState(() => _playbackPath = path);
    } catch (error) {
      if (mounted) {
        setState(() {
          _selection = previous;
          _error = error;
        });
        _showProjectMessage('切換音軌失敗：$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leavePractice() async {
    _countdownGeneration++;
    await _player.pause();
    if (mounted) {
      setState(() {
        _practicing = false;
        _restCountdown = null;
      });
    }
  }

  Future<void> _saveProject() async {
    final source = _source;
    final prepared = _prepared;
    if (source == null || prepared == null) return;
    var name = _savedProjectName;
    if (_savedProjectId == null) {
      name = await requestProjectName(context, initialValue: source.name);
      if (name == null || !mounted) return;
    }
    try {
      final project = await _projectStore.save(
        id: _savedProjectId,
        name: name!,
        mode: SavedProjectMode.musicPractice,
        data: {
          'source': {
            'path': source.path,
            'name': source.name,
            'kind': source.kind.name,
          },
          'prepared': {
            'originalWavPath': prepared.originalWavPath,
            'workspacePath': prepared.workspacePath,
            'durationMs': prepared.duration.inMilliseconds,
          },
          'separatedPaths': _separated?.paths.map(
            (stem, path) => MapEntry(stem.name, path),
          ),
          'selectionOriginal': _selection.original,
          'selectedStems': _selection.stems.map((stem) => stem.name).toList(),
          'practicing': _practicing,
          'playbackPath': _playbackPath,
          'positionMs': _position.inMilliseconds,
          'rate': _rate.value,
          'loopStartMs': _loop.start.inMilliseconds,
          'loopEndMs': _loop.end.inMilliseconds,
          'repeat': _repeat,
          'restMs': _rest.inMilliseconds,
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

  Future<void> _loadProject(SavedProject project) async {
    try {
      await _player.pause();
      _countdownGeneration++;
      final data = project.data;
      final sourceData = Map<String, Object?>.from(data['source'] as Map);
      final preparedData = Map<String, Object?>.from(data['prepared'] as Map);
      final source = MusicPracticeSource(
        path: sourceData['path'] as String,
        name: sourceData['name'] as String,
        kind: MusicPracticeInputKind.values.byName(
          sourceData['kind'] as String,
        ),
      );
      final prepared = PreparedMusic(
        source: source,
        originalWavPath: preparedData['originalWavPath'] as String,
        workspacePath: preparedData['workspacePath'] as String,
        duration: Duration(milliseconds: preparedData['durationMs'] as int),
      );
      if (!await File(prepared.originalWavPath).exists()) {
        throw StateError('找不到已準備的音訊');
      }
      final separatedData = data['separatedPaths'];
      SeparatedStems? separated;
      if (separatedData is Map) {
        final paths = <MusicStem, String>{};
        for (final entry in separatedData.entries) {
          final stem = MusicStem.values.byName(entry.key as String);
          final path = entry.value as String;
          if (await File(path).exists()) paths[stem] = path;
        }
        if (paths.length == MusicStem.values.length) {
          separated = SeparatedStems(prepared: prepared, paths: paths);
        }
      }
      final selectedNames = (data['selectedStems'] as List? ?? const [])
          .cast<String>()
          .toSet();
      final selectedStems = MusicStem.values
          .where((stem) => selectedNames.contains(stem.name))
          .toSet();
      final selection = ((data['selectionOriginal'] as bool?) ?? true)
          ? MusicTrackSelection.original()
          : MusicTrackSelection.stems(selectedStems);
      final practicing = (data['practicing'] as bool?) ?? false;
      String? playbackPath;
      if (practicing) {
        final savedPath = data['playbackPath'] as String?;
        if (savedPath != null && await File(savedPath).exists()) {
          playbackPath = savedPath;
        } else if (selection.original) {
          playbackPath = prepared.originalWavPath;
        } else if (separated != null && selectedStems.isNotEmpty) {
          playbackPath = await _mixBuilder.build(
            stems: separated,
            selection: selectedStems,
          );
        } else {
          throw StateError('找不到已分離的聲部檔案');
        }
        await _player.setFilePath(playbackPath);
      }
      final rate = PlaybackRate((data['rate'] as num).toDouble());
      await _player.setSpeed(rate.value);
      final duration = prepared.duration;
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
      if (practicing) await _player.seek(position);
      if (!mounted) return;
      setState(() {
        _source = source;
        _prepared = prepared;
        _separated = separated;
        _selection = selection;
        _busy = false;
        _error = null;
        _practicing = practicing;
        _settingsOpen = false;
        _handlingLoop = false;
        _position = position;
        _duration = duration;
        _loop = loop;
        _rate = rate;
        _repeat = (data['repeat'] as bool?) ?? false;
        _rest = Duration(milliseconds: (data['restMs'] as int?) ?? 0);
        _restCountdown = null;
        _playbackPath = playbackPath;
        _savedProjectId = project.id;
        _savedProjectName = project.name;
      });
      unawaited(_analyzeWaveforms());
      _showProjectMessage('已開啟「${project.name}」');
    } catch (error) {
      if (mounted) _showProjectMessage('無法開啟專案，部分音樂或分軌檔案已不存在。');
    }
  }

  void _showProjectMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  void dispose() {
    _countdownGeneration++;
    _waveformGeneration++;
    _positionSubscription?.cancel();
    _stateSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Stack(
      children: [
        Positioned.fill(
          child: _practicing ? _buildPractice() : _buildTrackSetup(),
        ),
        if (_restCountdown case final seconds?)
          Positioned.fill(child: _MusicRestOverlay(seconds: seconds)),
      ],
    ),
  );

  Widget _buildTrackSetup() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
    children: [
      Row(
        children: [
          const Icon(Icons.music_note, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '純音樂練習',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          SavedProjectControls(
            mode: SavedProjectMode.musicPractice,
            canSave: _prepared != null && !_busy,
            onSave: _saveProject,
            onLoad: _loadProject,
          ),
          TextButton.icon(
            onPressed: _busy ? null : _pickMedia,
            icon: const Icon(Icons.add),
            label: Text(_source == null ? '匯入' : '更換'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text('匯入影片或音訊，選擇原聲，或用 AI 分離並混合六種聲部。'),
      const SizedBox(height: 16),
      if (_source == null)
        _ImportMusicCard(onPressed: _pickMedia)
      else ...[
        Card(
          child: ListTile(
            leading: Icon(
              _source!.kind == MusicPracticeInputKind.video
                  ? Icons.video_file_outlined
                  : Icons.audio_file_outlined,
            ),
            title: Text(_source!.name),
            subtitle: Text(
              _prepared == null
                  ? '正在準備音訊…'
                  : '長度 ${formatDuration(_prepared!.duration)}',
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_prepared != null) _buildTrackSelector(),
      ],
      if (_busy && _progress != null) ...[
        const SizedBox(height: 16),
        _SeparationProgressCard(update: _progress!),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text('處理失敗：$_error'),
          ),
        ),
      ],
    ],
  );

  Widget _buildTrackSelector() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('選擇練習聲部', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ChoiceChip(
            selected: _selection.original,
            avatar: const Icon(Icons.library_music_outlined),
            label: const Text('原聲'),
            onSelected: _busy
                ? null
                : (_) =>
                      setState(() => _selection = _selection.selectOriginal()),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: MusicStem.values
                .map(
                  (stem) => FilterChip(
                    selected: _selection.stems.contains(stem),
                    avatar: Icon(_stemIcon(stem)),
                    label: Text(_stemLabel(stem)),
                    onSelected: _separated == null || _busy
                        ? null
                        : (_) => setState(
                            () => _selection = _selection.toggleStem(stem),
                          ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          if (_separated == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _splitStems,
                  icon: const Icon(Icons.graphic_eq),
                  label: const Text('分離六軌'),
                ),
                const SizedBox(height: 6),
                const Text(
                  '首次使用會下載約 136 MB 模型；處理完全在本機進行。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            )
          else
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                SizedBox(width: 6),
                Text('六軌分離完成，可多選混音'),
              ],
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _selection.canPractice && !_busy
                  ? _startPractice
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('進入循環練習'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildPractice() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
    child: Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '返回聲部選擇',
              onPressed: _leavePractice,
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                _selection.original
                    ? '原聲練習'
                    : _selection.stems.map(_stemLabel).join('＋'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SavedProjectControls(
              mode: SavedProjectMode.musicPractice,
              canSave: _prepared != null && !_busy,
              onSave: _saveProject,
              onLoad: _loadProject,
            ),
            TextButton(onPressed: _pickMedia, child: const Text('更換音樂')),
          ],
        ),
        Expanded(child: _buildWaveformPanel()),
        Row(
          children: [
            IconButton.filled(
              onPressed: _player.playing ? _player.pause : _player.play,
              icon: Icon(_player.playing ? Icons.pause : Icons.play_arrow),
            ),
            Expanded(
              child: PrecisionScrubSlider(
                position: _position,
                duration: _duration,
                onChangeStart: (_) => _player.pause(),
                onChanged: _player.seek,
                onChangeEnd: _player.seek,
              ),
            ),
            TimeText(_position),
          ],
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => setState(() => _settingsOpen = !_settingsOpen),
                child: SizedBox(
                  height: 38,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.tune, size: 18),
                      const SizedBox(width: 7),
                      const Text('循環練習設定'),
                      const SizedBox(width: 7),
                      Icon(
                        _settingsOpen
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: _settingsOpen
                    ? SizedBox(
                        height: (MediaQuery.sizeOf(context).height * 0.3).clamp(
                          170.0,
                          280.0,
                        ),
                        child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            PlaybackRateControl(
                              value: _rate,
                              onChanged: _setRate,
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('重複循環'),
                                    value: _repeat,
                                    onChanged: (value) =>
                                        setState(() => _repeat = value),
                                  ),
                                ),
                                IconButton.filledTonal(
                                  tooltip: '回到循環開頭',
                                  onPressed: () => _player.seek(_loop.start),
                                  icon: const Icon(Icons.skip_previous),
                                ),
                              ],
                            ),
                            Text(
                              '循環 ${formatDuration(_loop.start)} – '
                              '${formatDuration(_loop.end)}',
                            ),
                            RangeSlider(
                              values: RangeValues(
                                _loop.start.inMilliseconds.toDouble(),
                                _loop.end.inMilliseconds.toDouble(),
                              ),
                              max: _duration.inMilliseconds
                                  .clamp(1, 1 << 53)
                                  .toDouble(),
                              labels: RangeLabels(
                                formatDuration(_loop.start),
                                formatDuration(_loop.end),
                              ),
                              onChanged: _setLoop,
                            ),
                            Text('循環間休息 ${_rest.inSeconds} 秒'),
                            Slider(
                              value: _rest.inSeconds.toDouble(),
                              max: 30,
                              divisions: 30,
                              label: '${_rest.inSeconds} 秒',
                              onChanged: (value) => setState(
                                () => _rest = Duration(seconds: value.round()),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildWaveformPanel() {
    final prepared = _prepared;
    if (prepared == null) return const SizedBox.shrink();
    final separated = _separated;
    final tracks = separated == null
        ? [
            _WaveformTrack(
              label: '原聲',
              path: prepared.originalWavPath,
              color: Colors.deepPurpleAccent,
              selected: _selection.original,
              stem: null,
            ),
          ]
        : MusicStem.values
              .map(
                (stem) => _WaveformTrack(
                  label: _stemLabel(stem),
                  path: separated.paths[stem]!,
                  color: _stemColor(stem),
                  selected: _selection.stems.contains(stem),
                  stem: stem,
                ),
              )
              .toList();
    return _AlignedWaveformPanel(
      tracks: tracks,
      waveforms: _waveforms,
      loading: _waveformsLoading,
      error: _waveformError,
      position: _position,
      duration: _duration,
      loop: _loop,
      originalSelected: _selection.original,
      selectionEnabled: separated != null && !_busy,
      onSelectOriginal: () =>
          _switchPracticeSelection(MusicTrackSelection.original()),
      onToggleTrack: (track) {
        final stem = track.stem;
        if (stem != null) {
          _switchPracticeSelection(_selection.toggleStem(stem));
        }
      },
      onSeek: (position) {
        _countdownGeneration++;
        _player.pause();
        _player.seek(position);
      },
    );
  }

  Color _stemColor(MusicStem stem) => switch (stem) {
    MusicStem.drums => Colors.orangeAccent,
    MusicStem.bass => Colors.lightBlueAccent,
    MusicStem.other => Colors.blueGrey,
    MusicStem.vocals => Colors.pinkAccent,
    MusicStem.guitar => Colors.greenAccent,
    MusicStem.piano => Colors.amberAccent,
  };
}

final class _WaveformTrack {
  const _WaveformTrack({
    required this.label,
    required this.path,
    required this.color,
    required this.selected,
    required this.stem,
  });

  final String label;
  final String path;
  final Color color;
  final bool selected;
  final MusicStem? stem;
}

final class _AlignedWaveformPanel extends StatelessWidget {
  const _AlignedWaveformPanel({
    required this.tracks,
    required this.waveforms,
    required this.loading,
    required this.error,
    required this.position,
    required this.duration,
    required this.loop,
    required this.originalSelected,
    required this.selectionEnabled,
    required this.onSelectOriginal,
    required this.onToggleTrack,
    required this.onSeek,
  });

  final List<_WaveformTrack> tracks;
  final Map<String, List<double>> waveforms;
  final bool loading;
  final Object? error;
  final Duration position;
  final Duration duration;
  final TimeRange loop;
  final bool originalSelected;
  final bool selectionEnabled;
  final VoidCallback onSelectOriginal;
  final ValueChanged<_WaveformTrack> onToggleTrack;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              const Icon(Icons.stacked_line_chart, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '對齊音軌・點擊波形定位',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              FilterChip(
                visualDensity: VisualDensity.compact,
                selected: originalSelected,
                showCheckmark: false,
                avatar: const Icon(Icons.library_music_outlined, size: 16),
                label: const Text('原聲'),
                onSelected: selectionEnabled ? (_) => onSelectOriginal() : null,
              ),
              const SizedBox(width: 6),
              if (loading)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        if (error != null && waveforms.isEmpty)
          const Expanded(child: Center(child: Text('無法建立音軌波形')))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return SizedBox(
                  height: tracks.length == 1 ? 100 : 46,
                  child: _WaveformTrackRow(
                    track: track,
                    samples: waveforms[track.path],
                    position: position,
                    duration: duration,
                    loop: loop,
                    selectionEnabled: selectionEnabled,
                    onToggle: () => onToggleTrack(track),
                    onSeek: onSeek,
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
          child: Row(
            children: [
              const SizedBox(width: 62),
              const Text('0:00', style: TextStyle(fontSize: 10)),
              const Spacer(),
              Text(
                formatDuration(duration),
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _WaveformTrackRow extends StatelessWidget {
  const _WaveformTrackRow({
    required this.track,
    required this.samples,
    required this.position,
    required this.duration,
    required this.loop,
    required this.selectionEnabled,
    required this.onToggle,
    required this.onSeek,
  });

  final _WaveformTrack track;
  final List<double>? samples;
  final Duration position;
  final Duration duration;
  final TimeRange loop;
  final bool selectionEnabled;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;

  void _seek(double x, double width) {
    if (duration == Duration.zero || width <= 0) return;
    final fraction = (x / width).clamp(0.0, 1.0);
    onSeek(duration * fraction);
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 68,
        child: FilterChip(
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selected: track.selected,
          showCheckmark: false,
          selectedColor: track.color.withValues(alpha: 0.38),
          side: BorderSide(
            color: track.selected
                ? track.color
                : track.color.withValues(alpha: 0.35),
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          label: SizedBox(
            width: 38,
            child: Text(
              track.label,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10),
            ),
          ),
          onSelected: selectionEnabled && track.stem != null
              ? (_) => onToggle()
              : null,
        ),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _seek(details.localPosition.dx, constraints.maxWidth),
            onHorizontalDragStart: (details) =>
                _seek(details.localPosition.dx, constraints.maxWidth),
            onHorizontalDragUpdate: (details) =>
                _seek(details.localPosition.dx, constraints.maxWidth),
            child: CustomPaint(
              painter: _WaveformPainter(
                samples: samples,
                color: track.color,
                selected: track.selected,
                positionFraction: duration == Duration.zero
                    ? 0
                    : position.inMicroseconds / duration.inMicroseconds,
                loopStartFraction: duration == Duration.zero
                    ? 0
                    : loop.start.inMicroseconds / duration.inMicroseconds,
                loopEndFraction: duration == Duration.zero
                    ? 1
                    : loop.end.inMicroseconds / duration.inMicroseconds,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ],
  );
}

final class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.samples,
    required this.color,
    required this.selected,
    required this.positionFraction,
    required this.loopStartFraction,
    required this.loopEndFraction,
  });

  final List<double>? samples;
  final Color color;
  final bool selected;
  final double positionFraction;
  final double loopStartFraction;
  final double loopEndFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.height / 2;
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var division = 0; division <= 4; division++) {
      final x = size.width * division / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    canvas.drawLine(Offset(0, center), Offset(size.width, center), gridPaint);

    final values = samples;
    if (values == null || values.isEmpty) {
      final loadingPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(0, center),
        Offset(size.width, center),
        loadingPaint,
      );
    } else {
      final path = Path()..moveTo(0, center);
      for (var i = 0; i < values.length; i++) {
        final x = size.width * i / (values.length - 1).clamp(1, values.length);
        path.lineTo(x, center - values[i] * center * 0.88);
      }
      for (var i = values.length - 1; i >= 0; i--) {
        final x = size.width * i / (values.length - 1).clamp(1, values.length);
        path.lineTo(x, center + values[i] * center * 0.88);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: selected ? 0.85 : 0.48),
      );
    }

    final loopStart = size.width * loopStartFraction.clamp(0.0, 1.0);
    final loopEnd = size.width * loopEndFraction.clamp(0.0, 1.0);
    final outsidePaint = Paint()..color = Colors.black.withValues(alpha: 0.35);
    canvas.drawRect(Rect.fromLTRB(0, 0, loopStart, size.height), outsidePaint);
    canvas.drawRect(
      Rect.fromLTRB(loopEnd, 0, size.width, size.height),
      outsidePaint,
    );
    final boundaryPaint = Paint()
      ..color = Colors.deepPurpleAccent.withValues(alpha: 0.9)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(loopStart, 0),
      Offset(loopStart, size.height),
      boundaryPaint,
    );
    canvas.drawLine(
      Offset(loopEnd, 0),
      Offset(loopEnd, size.height),
      boundaryPaint,
    );

    final playhead = size.width * positionFraction.clamp(0.0, 1.0);
    canvas.drawLine(
      Offset(playhead, 0),
      Offset(playhead, size.height),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.color != color ||
      oldDelegate.selected != selected ||
      oldDelegate.positionFraction != positionFraction ||
      oldDelegate.loopStartFraction != loopStartFraction ||
      oldDelegate.loopEndFraction != loopEndFraction;
}

final class _ImportMusicCard extends StatelessWidget {
  const _ImportMusicCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
      child: Column(
        children: [
          const Icon(Icons.queue_music, size: 72),
          const SizedBox(height: 12),
          Text('選擇練習音樂', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('支援影片與 MP3、WAV、M4A、AAC、FLAC、OGG'),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.file_open),
            label: const Text('匯入影片或聲音檔'),
          ),
        ],
      ),
    ),
  );
}

final class _SeparationProgressCard extends StatelessWidget {
  const _SeparationProgressCard({required this.update});

  final StemSeparationUpdate update;

  @override
  Widget build(BuildContext context) {
    final label = switch (update.stage) {
      StemSeparationStage.preparingAudio => '正在準備 44.1 kHz 音訊',
      StemSeparationStage.downloadingModel => '正在下載 AI 六軌分離模型',
      StemSeparationStage.separating => '正在本機分離六軌',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: update.progress),
            const SizedBox(height: 6),
            Text('${(update.progress * 100).round()}%'),
          ],
        ),
      ),
    );
  }
}

final class _MusicRestOverlay extends StatelessWidget {
  const _MusicRestOverlay({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.self_improvement, size: 48),
            const Text('休息'),
            Text(
              '$seconds',
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Text('下一輪即將開始'),
          ],
        ),
      ),
    ),
  );
}

String _stemLabel(MusicStem stem) => switch (stem) {
  MusicStem.drums => '鼓組',
  MusicStem.bass => '貝斯',
  MusicStem.other => '其他樂器',
  MusicStem.vocals => '人聲',
  MusicStem.guitar => '吉他',
  MusicStem.piano => '鋼琴',
};

IconData _stemIcon(MusicStem stem) => switch (stem) {
  MusicStem.drums => Icons.album,
  MusicStem.bass => Icons.music_note,
  MusicStem.other => Icons.auto_awesome,
  MusicStem.vocals => Icons.mic,
  MusicStem.guitar => Icons.music_note,
  MusicStem.piano => Icons.piano,
};
