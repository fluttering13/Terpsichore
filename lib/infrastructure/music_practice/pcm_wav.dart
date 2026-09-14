import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

final class Pcm16StereoWavReader {
  Pcm16StereoWavReader._({
    required this._file,
    required this.sampleRate,
    required this.frameCount,
    required this._dataOffset,
  });

  final RandomAccessFile _file;
  final int _dataOffset;
  final int sampleRate;
  final int frameCount;

  static Future<Pcm16StereoWavReader> open(String path) async {
    final file = await File(path).open();
    try {
      final riff = await file.read(12);
      if (riff.length != 12 ||
          _ascii(riff, 0, 4) != 'RIFF' ||
          _ascii(riff, 8, 4) != 'WAVE') {
        throw const FormatException('不是有效的 WAV 檔案');
      }

      int? sampleRate;
      int? channels;
      int? bitsPerSample;
      int? format;
      int? dataOffset;
      int? dataSize;
      while (await file.position() + 8 <= await file.length()) {
        final header = await file.read(8);
        if (header.length != 8) break;
        final id = _ascii(header, 0, 4);
        final size = ByteData.sublistView(header).getUint32(4, Endian.little);
        if (id == 'fmt ') {
          final bytes = await file.read(size);
          if (bytes.length < 16) throw const FormatException('WAV fmt 區塊不完整');
          final data = ByteData.sublistView(bytes);
          format = data.getUint16(0, Endian.little);
          channels = data.getUint16(2, Endian.little);
          sampleRate = data.getUint32(4, Endian.little);
          bitsPerSample = data.getUint16(14, Endian.little);
        } else if (id == 'data') {
          dataOffset = await file.position();
          dataSize = size;
          break;
        } else {
          await file.setPosition(
            await file.position() + size + (size.isOdd ? 1 : 0),
          );
        }
      }
      if (format != 1 || channels != 2 || bitsPerSample != 16) {
        throw const FormatException('分軌輸入必須是 PCM 16-bit 雙聲道 WAV');
      }
      if (sampleRate != 44100 || dataOffset == null || dataSize == null) {
        throw const FormatException('分軌輸入必須是 44.1 kHz WAV');
      }
      return Pcm16StereoWavReader._(
        file: file,
        sampleRate: sampleRate!,
        frameCount: dataSize ~/ 4,
        dataOffset: dataOffset,
      );
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  Future<Float32List> readPlanarFrames(int start, int count) async {
    final available = math
        .min(count, frameCount - start)
        .clamp(0, count)
        .toInt();
    await _file.setPosition(_dataOffset + start * 4);
    final bytes = await _file.read(available * 4);
    final data = ByteData.sublistView(bytes);
    final result = Float32List(count * 2);
    for (var frame = 0; frame < available; frame++) {
      result[frame] = data.getInt16(frame * 4, Endian.little) / 32768.0;
      result[count + frame] =
          data.getInt16(frame * 4 + 2, Endian.little) / 32768.0;
    }
    return result;
  }

  Future<void> close() => _file.close();

  static String _ascii(Uint8List bytes, int start, int length) =>
      String.fromCharCodes(bytes.sublist(start, start + length));
}

final class Pcm16StereoWavWriter {
  Pcm16StereoWavWriter._(this._file);

  final RandomAccessFile _file;

  static Future<Pcm16StereoWavWriter> create(
    String path, {
    required int frameCount,
  }) async {
    final file = await File(path).open(mode: FileMode.write);
    await file.writeFrom(_header(frameCount));
    return Pcm16StereoWavWriter._(file);
  }

  Future<void> writeStereo(
    int frameCount,
    double Function(int frame) left,
    double Function(int frame) right,
  ) async {
    if (frameCount <= 0) return;
    final bytes = Uint8List(frameCount * 4);
    final data = ByteData.sublistView(bytes);
    for (var frame = 0; frame < frameCount; frame++) {
      data.setInt16(frame * 4, _pcm16(left(frame)), Endian.little);
      data.setInt16(frame * 4 + 2, _pcm16(right(frame)), Endian.little);
    }
    await _file.writeFrom(bytes);
  }

  Future<void> close() => _file.close();

  static int _pcm16(double value) =>
      (value.clamp(-1.0, 1.0) * 32767).round().clamp(-32768, 32767);

  static Uint8List _header(int frames) {
    final dataSize = frames * 4;
    final bytes = Uint8List(44);
    bytes.setRange(0, 4, 'RIFF'.codeUnits);
    bytes.setRange(8, 12, 'WAVE'.codeUnits);
    bytes.setRange(12, 16, 'fmt '.codeUnits);
    bytes.setRange(36, 40, 'data'.codeUnits);
    final data = ByteData.sublistView(bytes);
    data.setUint32(4, 36 + dataSize, Endian.little);
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 2, Endian.little);
    data.setUint32(24, 44100, Endian.little);
    data.setUint32(28, 44100 * 4, Endian.little);
    data.setUint16(32, 4, Endian.little);
    data.setUint16(34, 16, Endian.little);
    data.setUint32(40, dataSize, Endian.little);
    return bytes;
  }
}
