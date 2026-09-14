import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../../core/music_practice/stem_separation.dart';
import 'htdemucs_model_store.dart';
import 'pcm_wav.dart';

final class HtdemucsOnnxStemSeparator implements MusicStemSeparator {
  const HtdemucsOnnxStemSeparator({
    this._modelStore = const HtdemucsModelStore(),
  });

  static const sampleCount = 343980;
  static const overlap = sampleCount ~/ 4;
  static const stride = sampleCount - overlap;

  final HtdemucsModelStore _modelStore;

  @override
  Future<SeparatedStems> separate(
    PreparedMusic music, {
    required void Function(StemSeparationUpdate update) onProgress,
  }) async {
    final paths = {
      for (final stem in MusicStem.values)
        stem: '${music.workspacePath}/${stem.name}.wav',
    };
    if (await _allOutputsExist(paths)) {
      onProgress(
        const StemSeparationUpdate(
          stage: StemSeparationStage.separating,
          progress: 1,
        ),
      );
      return SeparatedStems(prepared: music, paths: paths);
    }

    final modelPath = await _modelStore.obtain(onProgress: onProgress);
    final reader = await Pcm16StereoWavReader.open(music.originalWavPath);
    final writers = <MusicStem, Pcm16StereoWavWriter>{};
    OrtSession? session;
    try {
      for (final entry in paths.entries) {
        writers[entry.key] = await Pcm16StereoWavWriter.create(
          entry.value,
          frameCount: reader.frameCount,
        );
      }
      session = await OnnxRuntime().createSession(
        modelPath,
        options: OrtSessionOptions(
          intraOpNumThreads: 2,
          interOpNumThreads: 1,
          useArena: true,
        ),
      );

      final chunkCount = math.max(
        1,
        (reader.frameCount + stride - 1) ~/ stride,
      );
      final window = _makeWindow();
      final previousTails = <MusicStem, Float32List>{};
      var previousTailLength = 0;
      for (var chunkIndex = 0; chunkIndex < chunkCount; chunkIndex++) {
        final start = chunkIndex * stride;
        final chunkLength = math.min(sampleCount, reader.frameCount - start);
        final inputData = await reader.readPlanarFrames(start, sampleCount);
        final input = await OrtValue.fromList(inputData, const [
          1,
          2,
          sampleCount,
        ]);
        OrtValue? output;
        try {
          final outputs = await session.run({'mix': input});
          output = outputs['stems'];
          if (output == null) throw StateError('AI 分離沒有回傳聲部輸出');
          final values = await output.asFlattenedList();
          if (values.length != MusicStem.values.length * 2 * sampleCount) {
            throw StateError('AI 分離回傳了非預期的輸出大小');
          }
          final lastChunk = start + stride >= reader.frameCount;
          for (final stem in MusicStem.values) {
            final writer = writers[stem]!;
            final channelBase = stem.index * 2 * sampleCount;
            var emitted = 0;
            if (chunkIndex == 0) {
              emitted = math.min(stride, chunkLength);
              await _writeDirect(
                writer,
                values,
                channelBase,
                startInChunk: 0,
                frameCount: emitted,
              );
            } else {
              final overlapLength = math.min(
                math.min(overlap, chunkLength),
                previousTailLength,
              );
              final tail = previousTails[stem]!;
              await writer.writeStereo(
                overlapLength,
                (frame) {
                  final denominator = window[stride + frame] + window[frame];
                  if (denominator <= 1e-8) return 0;
                  return (tail[frame] +
                          (values[channelBase + frame] as num).toDouble() *
                              window[frame]) /
                      denominator;
                },
                (frame) {
                  final denominator = window[stride + frame] + window[frame];
                  if (denominator <= 1e-8) return 0;
                  return (tail[previousTailLength + frame] +
                          (values[channelBase + sampleCount + frame] as num)
                                  .toDouble() *
                              window[frame]) /
                      denominator;
                },
              );
              final middleEnd = math.min(stride, chunkLength);
              await _writeDirect(
                writer,
                values,
                channelBase,
                startInChunk: overlapLength,
                frameCount: middleEnd - overlapLength,
              );
              emitted = middleEnd;
            }

            if (lastChunk) {
              await _writeDirect(
                writer,
                values,
                channelBase,
                startInChunk: emitted,
                frameCount: chunkLength - emitted,
              );
            } else {
              final tailLength = chunkLength - stride;
              final tail = Float32List(tailLength * 2);
              for (var frame = 0; frame < tailLength; frame++) {
                final chunkFrame = stride + frame;
                final weight = window[chunkFrame];
                tail[frame] =
                    (values[channelBase + chunkFrame] as num).toDouble() *
                    weight;
                tail[tailLength + frame] =
                    (values[channelBase + sampleCount + chunkFrame] as num)
                        .toDouble() *
                    weight;
              }
              previousTails[stem] = tail;
            }
          }
          previousTailLength = lastChunk ? 0 : chunkLength - stride;
        } finally {
          await output?.dispose();
          await input.dispose();
        }
        onProgress(
          StemSeparationUpdate(
            stage: StemSeparationStage.separating,
            progress: (chunkIndex + 1) / chunkCount,
          ),
        );
      }
    } catch (_) {
      for (final path in paths.values) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      rethrow;
    } finally {
      await session?.close();
      await reader.close();
      for (final writer in writers.values) {
        await writer.close();
      }
    }
    return SeparatedStems(prepared: music, paths: paths);
  }

  Future<void> _writeDirect(
    Pcm16StereoWavWriter writer,
    List<dynamic> values,
    int channelBase, {
    required int startInChunk,
    required int frameCount,
  }) => writer.writeStereo(
    frameCount,
    (frame) => (values[channelBase + startInChunk + frame] as num).toDouble(),
    (frame) => (values[channelBase + sampleCount + startInChunk + frame] as num)
        .toDouble(),
  );

  Float32List _makeWindow() {
    final window = Float32List(sampleCount);
    window.fillRange(0, sampleCount, 1);
    for (var index = 0; index < overlap; index++) {
      final value = index / (overlap - 1);
      window[index] = value;
      window[sampleCount - 1 - index] = value;
    }
    return window;
  }

  Future<bool> _allOutputsExist(Map<MusicStem, String> paths) async {
    for (final path in paths.values) {
      final file = File(path);
      if (!await file.exists() || await file.length() <= 44) return false;
    }
    return true;
  }
}
