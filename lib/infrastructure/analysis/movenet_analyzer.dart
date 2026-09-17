import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'int8_pose_session.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/ab_analysis/pose_alignment.dart';
import '../../core/ab_analysis/movenet_processing.dart';
import '../../core/ab_analysis/pose_sampling.dart';
import '../../core/ab_analysis/pose_stream_tracker.dart';
import '../../core/ab_analysis/thunder_crop_tracking.dart'
    show thunderFullFrame;
import 'pose_crop_worker.dart';

final class PoseAnalysisCancelled implements Exception {}

/// Accurate (Android) or INT8 (other native platforms). One inference per sample.
/// Two bounded disk chunks and one independent model session per video.
final class MoveNetAnalyzer {
  /// Production policy. ML Kit owns tracking; do not layer Thunder retries on it.
  factory MoveNetAnalyzer.forApp({
    required bool isAndroid,
    required bool trackMainPerson,
  }) => MoveNetAnalyzer(
    multiPersonFiltering: !isAndroid && trackMainPerson,
    nativeBackend: isAndroid
        ? (trackMainPerson ? 'mlkit-accurate' : 'mlkit-accurate-single')
        : 'int8',
    nativeParallelBackend: isAndroid,
    intraOpThreads: 1,
  );

  MoveNetAnalyzer({
    this.multiPersonFiltering = true,
    this.intraOpThreads = 2,
    this.nativeParallelBackend = false,
    this.nativeBackend = 'int8',
  });
  final String nativeBackend;
  final bool nativeParallelBackend;
  static const _native = MethodChannel('terpsichore/mlkit_pose');
  String? _nativeSession;
  final nativeIntervals = <List<int>>[];
  final int intraOpThreads;
  final bool multiPersonFiltering;
  final Map<String, int> metrics = {};
  final Set<int> _decoders = {};
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  set cancelled(bool value) {
    _cancelled = value;
    if (value) {
      for (final id in _decoders.toList()) {
        unawaited(FFmpegKit.cancel(id).catchError((Object _) {}));
      }
    }
  }

  void _record(String key, int value) =>
      metrics.update(key, (n) => n + value, ifAbsent: () => value);
  void _check() {
    if (cancelled) throw PoseAnalysisCancelled();
  }

  Future<PoseSequence> analyze({
    required String path,
    required double start,
    required double end,
    required double aspectRatio,
    int? samplingFps,
    required void Function(double) onProgress,
  }) async {
    _check();
    if (nativeParallelBackend
        ? !['mlkit-accurate', 'mlkit-accurate-single'].contains(nativeBackend)
        : nativeBackend != 'int8') {
      throw ArgumentError.value(
        nativeBackend,
        'nativeBackend',
        'Retired pose backend',
      );
    }
    if (intraOpThreads < 1 || intraOpThreads > 4) {
      throw ArgumentError.value(
        intraOpThreads,
        'intraOpThreads',
        'Must be 1–4',
      );
    }
    if (![start, end, aspectRatio].every((v) => v.isFinite) ||
        start < 0 ||
        end <= start ||
        end - start > 60 ||
        aspectRatio <= 0 ||
        (samplingFps != null && (samplingFps < 6 || samplingFps > 30))) {
      throw ArgumentError('請選擇不超過 60 秒的分析片段');
    }
    metrics.clear();
    nativeIntervals.clear();
    metrics['native_parallel_backend'] = nativeParallelBackend ? 1 : 0;
    metrics['intra_op_threads'] = intraOpThreads;
    metrics['multi_person_filtering'] = multiPersonFiltering ? 1 : 0;
    metrics['retry_calls'] = 0;
    final fps = samplingFps ?? 12;
    metrics['sampling_fps'] = fps;
    metrics['adaptive_sampling'] = samplingFps == null ? 1 : 0;
    final total = Stopwatch()..start();
    final workspace = await (await getTemporaryDirectory()).createTemp(
      'thunder-only-',
    );
    Int8PoseSession? session;
    PoseCropWorker? worker;
    Future<(File?, Object?)>? pending;
    try {
      final setup = Stopwatch()..start();
      if (nativeParallelBackend) {
        _nativeSession = await _native.invokeMethod<String>('create', {
          'threads': intraOpThreads,
          'backend': nativeBackend,
        });
      } else {
        session = await Int8PoseSession.open(intraOpThreads);
      }
      _check();
      if (!nativeParallelBackend) worker = await PoseCropWorker.start();
      _record('setup_us', setup.elapsedMicroseconds);
      final frames = <PoseFrame>[];
      final sampling = PoseSamplingPolicy(end - start);
      final tracker = PoseStreamTracker(aspectRatio);
      // Keep raw-buffer size bounded even when the user requests 30 FPS.
      final chunkSeconds = math.min(2.0, 24 / fps);
      final chunks = ((end - start) / chunkSeconds).ceil();
      Future<(File?, Object?)> decode(int index) => _decode(
        path,
        start + index * chunkSeconds,
        math.min(chunkSeconds, end - (start + index * chunkSeconds)),
        File('${workspace.path}/chunk-${index % 2}.bgr'),
        fps,
      );
      pending = decode(0);
      for (var chunk = 0; chunk < chunks; chunk++) {
        final decoded = await pending!;
        pending = null;
        _check();
        if (decoded.$2 != null) throw decoded.$2!;
        final io = Stopwatch()..start();
        final bytes = await decoded.$1!.readAsBytes();
        _record('file_read_us', io.elapsedMicroseconds);
        const frameBytes = 640 * 640 * 3;
        if (bytes.isEmpty || bytes.length % frameBytes != 0) {
          throw StateError('影片影格資料不完整');
        }
        if (chunk + 1 < chunks) pending = decode(chunk + 1);
        for (var i = 0; i < bytes.length ~/ frameBytes; i++) {
          _check();
          final seconds = start + chunk * chunkSeconds + i / fps;
          if (seconds >= end) break;
          if (samplingFps == null && !sampling.shouldInfer(i)) continue;
          PoseFrame best;
          if (nativeParallelBackend) {
            final output = await _inferNative({
              'bgr': Uint8List.sublistView(
                bytes,
                i * frameBytes,
                (i + 1) * frameBytes,
              ),
            });
            best = restoreMoveNet(
              decodeMoveNet(output, thunderFullFrame, seconds, 1),
              aspectRatio,
              0,
            );
          } else {
            final roi = multiPersonFiltering
                ? tracker.cropFor(seconds)
                : thunderFullFrame;
            final prep = Stopwatch()..start();
            final prepared = await worker!.crop(
              Uint8List.sublistView(
                bytes,
                i * frameBytes,
                (i + 1) * frameBytes,
              ),
              roi,
              0,
            );
            _record('crop_transfer_wait_us', prep.elapsedMicroseconds);
            _record('crop_worker_us', prepared.$2);
            _check();
            final output = await _infer(session, prepared.$1);
            best = restoreMoveNet(
              decodeMoveNet(output, roi, seconds, 1),
              aspectRatio,
              0,
            );
            if (multiPersonFiltering && !tracker.observe(best)) {
              _record('track_lost_frames', 1);
            }
          }
          _record('initial_calls', 1);
          _check();
          frames.add(best);
          sampling.observe(best);
          _record('frames', 1);
          _check();
          onProgress(
            ((seconds - start + 1 / fps) / (end - start)).clamp(0.0, 1.0),
          );
        }
      }
      _record('first_pass_us', total.elapsedMicroseconds);
      return PoseSequence(frames, aspectRatio);
    } finally {
      for (final id in _decoders.toList()) {
        await FFmpegKit.cancel(id);
      }
      // Prefetch returns errors as values. Await it before deleting our workspace.
      await pending;
      worker?.close();
      try {
        if (_nativeSession != null) {
          await _native.invokeMethod<void>('close', {'id': _nativeSession});
          _nativeSession = null;
        }
        await session?.close();
      } finally {
        await workspace.delete(recursive: true);
      }
      _record('total_us', total.elapsedMicroseconds);
    }
  }

  Future<(File?, Object?)> _decode(
    String path,
    double start,
    double length,
    File file,
    int fps,
  ) async {
    final timer = Stopwatch()..start();
    int? id;
    try {
      _check();
      final done = Completer<FFmpegSession>();
      final session = await FFmpegKit.executeWithArgumentsAsync(
        [
          '-y',
          '-v',
          'error',
          '-ss',
          start.toStringAsFixed(6),
          '-i',
          path,
          '-t',
          length.toStringAsFixed(6),
          '-an',
          '-sn',
          '-dn',
          '-vf',
          'fps=$fps:start_time=0,scale=640:640:force_original_aspect_ratio=decrease,pad=640:640:(ow-iw)/2:(oh-ih)/2:color=0x727272,setsar=1',
          '-pix_fmt',
          'bgr24',
          '-f',
          'rawvideo',
          file.path,
        ],
        (session) {
          if (!done.isCompleted) done.complete(session);
        },
      );
      id = session.getSessionId()!;
      _decoders.add(id);
      if (cancelled) await FFmpegKit.cancel(id);
      final completed = await done.future;
      _check();
      if (!ReturnCode.isSuccess(await completed.getReturnCode())) {
        throw StateError('無法讀取影片影格');
      }
      return (file, null);
    } catch (error) {
      return (null, error);
    } finally {
      if (id != null) _decoders.remove(id);
      _record('decode_us', timer.elapsedMicroseconds);
    }
  }

  Future<List<double>> _inferNative(Map<String, Object> input) async {
    final timer = Stopwatch()..start();
    _record('thunder_calls', 1);
    final result = (await _native.invokeMapMethod<String, dynamic>('run', {
      'id': _nativeSession,
      ...input,
    }))!;
    final start = result['start_ns'] as int, end = result['end_ns'] as int;
    nativeIntervals.add([start, end]);
    _record('native_compute_us', (end - start) ~/ 1000);
    metrics['native_peak_runs'] = result['peak_runs'] as int;
    _record('thunder_run_us', timer.elapsedMicroseconds);
    return (result['points'] as List)
        .cast<num>()
        .map((n) => n.toDouble())
        .toList();
  }

  Future<List<double>> _infer(Int8PoseSession? session, Int32List data) async {
    final timer = Stopwatch()..start();
    _record('thunder_calls', 1);
    final output = await session!.run(data);
    _record('thunder_run_us', timer.elapsedMicroseconds);
    return output;
  }
}
