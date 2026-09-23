import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// Compare cache copies off the UI isolate, without loading whole videos.
Future<bool> isSameVideo(
  String a,
  String b, {
  Future<String?> Function(String) fingerprint = _mediaFingerprint,
}) async {
  if (await compute(_compareFiles, (a, b))) return true;
  // A remux can change container IDs/timestamps while preserving every packet.
  final first = await fingerprint(a);
  if (first == null) return false;
  final second = await fingerprint(b);
  return second != null && first == second;
}

Future<String?> _mediaFingerprint(String path) async {
  Directory? directory;
  try {
    if (!await File(path).exists()) return null;
    directory = await (await getTemporaryDirectory()).createTemp(
      'video_identity_',
    );
    final output = File('${directory.path}/streams.sha256');
    final session = await FFmpegKit.executeWithArguments([
      '-v',
      'error',
      '-i',
      path,
      '-map',
      '0:v:0',
      '-map',
      '0:a?',
      '-c',
      'copy',
      '-f',
      'streamhash',
      '-hash',
      'sha256',
      output.path,
    ]);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) return null;
    final hash = (await output.readAsString()).trim();
    return hash.contains(',v,SHA256=') ? hash : null;
  } catch (_) {
    return null;
  } finally {
    if (directory != null) {
      try {
        final output = File('${directory.path}/streams.sha256');
        if (await output.exists()) await output.delete();
        await directory.delete();
      } on FileSystemException {
        // Only a temporary fingerprint remains if cleanup is interrupted.
      }
    }
  }
}

bool _compareFiles((String, String) paths) {
  final (a, b) = paths;
  if (a == b) return true;
  try {
    final first = File(a);
    final second = File(b);
    if (first.lengthSync() != second.lengthSync()) return false;
    final left = first.openSync();
    try {
      final right = second.openSync();
      try {
        while (true) {
          final x = left.readSync(65536);
          final y = right.readSync(65536);
          if (!listEquals(x, y)) return false;
          if (x.isEmpty) return true;
        }
      } finally {
        right.closeSync();
      }
    } finally {
      left.closeSync();
    }
  } on FileSystemException {
    return false;
  }
}
