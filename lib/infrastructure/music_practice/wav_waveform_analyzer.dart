import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'pcm_wav.dart';

final class WavWaveformAnalyzer {
  const WavWaveformAnalyzer();

  Future<List<double>> analyze(String path, {int bins = 600}) async {
    final source = File(path);
    final stat = await source.stat();
    final cache = File('$path.waveform-$bins.json');
    if (await cache.exists()) {
      try {
        final json = jsonDecode(await cache.readAsString()) as Map;
        if (json['version'] == 1 &&
            json['sourceSize'] == stat.size &&
            json['sourceModifiedMs'] == stat.modified.millisecondsSinceEpoch) {
          return (json['samples'] as List)
              .map((value) => (value as num).toDouble())
              .toList(growable: false);
        }
      } catch (_) {
        // A stale or interrupted cache is harmless; rebuild it from the WAV.
      }
    }

    final reader = await Pcm16StereoWavReader.open(path);
    try {
      final frameCount = reader.frameCount;
      if (frameCount == 0) return List.filled(bins, 0);
      final framesPerBin = (frameCount / bins).ceil();
      final samples = List<double>.filled(bins, 0);
      var maximum = 0.0;
      for (var bin = 0; bin < bins; bin++) {
        final start = bin * framesPerBin;
        if (start >= frameCount) break;
        final count = math.min(framesPerBin, frameCount - start);
        final frames = await reader.readPlanarFrames(start, count);
        var energy = 0.0;
        for (var frame = 0; frame < count; frame++) {
          final left = frames[frame];
          final right = frames[count + frame];
          energy += left * left + right * right;
        }
        final rms = math.sqrt(energy / (count * 2));
        samples[bin] = rms;
        maximum = math.max(maximum, rms);
      }
      if (maximum > 0) {
        for (var i = 0; i < samples.length; i++) {
          // A square-root display curve keeps quiet instruments visible while
          // preserving the timing of energy peaks.
          samples[i] = math.sqrt(samples[i] / maximum);
        }
      }
      await cache.writeAsString(
        jsonEncode({
          'version': 1,
          'sourceSize': stat.size,
          'sourceModifiedMs': stat.modified.millisecondsSinceEpoch,
          'samples': samples,
        }),
      );
      return samples;
    } finally {
      await reader.close();
    }
  }
}
