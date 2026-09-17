import 'dart:isolate';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Owns one interpreter per video; inference never blocks Flutter's UI isolate.
final class Int8PoseSession {
  Int8PoseSession._(this._interpreter);
  final Interpreter _interpreter;
  bool _closed = false;
  Future<List<double>>? _running;

  static Future<Int8PoseSession> open(int threads) async {
    final options = InterpreterOptions()..threads = threads;
    final interpreter = await Interpreter.fromAsset(
      'asset/models/movenet-thunder-int8.tflite',
      options: options,
    );
    try {
      if (interpreter.getInputTensor(0).type != TensorType.uint8 ||
          interpreter.getInputTensor(0).shape.join(',') != '1,256,256,3' ||
          interpreter.getOutputTensor(0).type != TensorType.float32 ||
          interpreter.getOutputTensor(0).shape.join(',') != '1,1,17,3') {
        throw StateError('Unexpected Thunder INT8 tensor format');
      }
      return Int8PoseSession._(interpreter);
    } catch (_) {
      interpreter.close();
      rethrow;
    } finally {
      options.delete();
    }
  }

  Future<List<double>> run(Int32List pixels) async {
    if (_closed || _running != null) throw StateError('Session closed or busy');
    if (pixels.length != 256 * 256 * 3) {
      throw ArgumentError('Invalid RGB tensor');
    }
    final address = _interpreter.address;
    final bytes = Uint8List.fromList(pixels);
    final pending = Isolate.run(() => _run(address, bytes));
    _running = pending;
    try {
      return await pending;
    } finally {
      _running = null;
    }
  }

  static List<double> _run(int address, Uint8List input) {
    final interpreter = Interpreter.fromAddress(address);
    final output = Float32List(51);
    interpreter.run(input.buffer, output.buffer);
    // The owner closes this pointer only after the isolate finishes.
    return output.toList();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _running;
    } finally {
      _interpreter.close();
    }
  }
}
