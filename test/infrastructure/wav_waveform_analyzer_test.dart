import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/infrastructure/music_practice/pcm_wav.dart';
import 'package:terpsichore/infrastructure/music_practice/wav_waveform_analyzer.dart';

void main() {
  test('waveform bins preserve the timing of amplitude peaks', () async {
    final directory = await Directory.systemTemp.createTemp('waveform_test_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/levels.wav';
    const framesPerSection = 100;
    const levels = [0.1, 0.8, 0.2, 0.4];
    final writer = await Pcm16StereoWavWriter.create(
      path,
      frameCount: framesPerSection * levels.length,
    );
    await writer.writeStereo(
      framesPerSection * levels.length,
      (frame) => levels[frame ~/ framesPerSection],
      (frame) => levels[frame ~/ framesPerSection],
    );
    await writer.close();

    final samples = await const WavWaveformAnalyzer().analyze(path, bins: 4);

    expect(samples, hasLength(4));
    expect(samples[1], 1);
    expect(samples[0], lessThan(samples[2]));
    expect(samples[2], lessThan(samples[3]));
    expect(File('$path.waveform-4.json').existsSync(), isTrue);
  });
}
