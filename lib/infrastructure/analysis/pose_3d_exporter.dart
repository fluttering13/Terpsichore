import 'dart:io';
import 'dart:ui' as ui;
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/session_state.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/ab_analysis/pose_3d.dart';
import '../../entrypoints/mobile/widgets/pose_3d_view.dart';
import 'pose_3d_analyzer.dart';

final class Pose3dExporter {
  bool cancelled = false;
  int? _sessionId;
  Future<void> cancel() async {
    cancelled = true;
    final id = _sessionId;
    if (id != null) await FFmpegKit.cancel(id);
  }

  void _check() {
    if (cancelled) throw Pose3dCancelled();
  }

  Future<File> export(
    Pose3dComparison data,
    Pose3dCamera camera,
    void Function(double) progress,
  ) async {
    final temp = await (await getTemporaryDirectory()).createTemp(
      'pose3d-export-',
    );
    final output = File(
      '${(await getTemporaryDirectory()).path}/pose3d-${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    Pose3dRenderer? renderer;
    try {
      renderer = await Pose3dRenderer.load();
      const fps = 30;
      final count = (data.seconds * fps).ceil();
      for (var i = 0; i < count; i++) {
        _check();
        final t = i / fps;
        final recorder = ui.PictureRecorder();
        Pose3dPainter(
          data.a.at(t, interpolate: data.settings.interpolate),
          data.b.at(t, interpolate: data.settings.interpolate),
          camera,
          renderer: renderer,
        ).paint(ui.Canvas(recorder), const ui.Size(720, 720));
        final picture = recorder.endRecording();
        final image = await picture.toImage(720, 720);
        picture.dispose();
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null) throw StateError('無法繪製 3D 影格');
          await File(
            '${temp.path}/${i.toString().padLeft(6, '0')}.png',
          ).writeAsBytes(png.buffer.asUint8List());
        } finally {
          image.dispose();
        }
        progress((i + 1) / count * .85);
      }
      _check();
      final session = await FFmpegKit.executeWithArgumentsAsync([
        '-y',
        '-framerate',
        '$fps',
        '-i',
        '${temp.path}/%06d.png',
        '-t',
        '${data.seconds}',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '20',
        '-pix_fmt',
        'yuv420p',
        '-movflags',
        '+faststart',
        output.path,
      ]);
      _sessionId = session.getSessionId();
      if (cancelled) await FFmpegKit.cancel(_sessionId!);
      // Async FFmpeg completion is polled without blocking UI or swallowing cancel.
      while (await session.getReturnCode() == null) {
        if (await session.getState() == SessionState.failed) {
          throw StateError('3D 影片輸出失敗');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      _check();
      if (!ReturnCode.isSuccess(await session.getReturnCode()) ||
          !await output.exists()) {
        throw StateError('3D 影片輸出失敗');
      }
      progress(1);
      return output;
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      renderer?.dispose();
      _sessionId = null;
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }
}
