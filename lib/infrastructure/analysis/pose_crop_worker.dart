import 'dart:isolate';
import 'dart:typed_data';
import '../../core/ab_analysis/movenet_processing.dart';
import '../../core/ab_analysis/rtmpose_processing.dart';

/// Persistent frame storage across direction retries; transferable typed buffers.
final class PoseCropWorker {
  PoseCropWorker._(this._isolate, this._port);
  final Isolate _isolate;
  final SendPort _port;
  bool _closed = false;
  static Future<PoseCropWorker> start() async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_entry, ready.sendPort);
    try {
      return PoseCropWorker._(
        isolate,
        await ready.first.timeout(const Duration(seconds: 10)) as SendPort,
      );
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      ready.close();
    }
  }

  Future<(Int32List, int)> crop(
    Uint8List? frame,
    PersonBox box,
    int rotation,
  ) async {
    if (_closed) throw StateError('Crop worker closed');
    final response = ReceivePort();
    try {
      _port.send([
        response.sendPort,
        frame == null ? null : TransferableTypedData.fromList([frame]),
        box,
        rotation,
      ]);
      final result =
          await response.first.timeout(const Duration(seconds: 30)) as List;
      if (result[0] is String) throw StateError(result[0] as String);
      return (
        (result[0] as TransferableTypedData).materialize().asInt32List(),
        result[1] as int,
      );
    } finally {
      response.close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _isolate.kill(priority: Isolate.immediate);
  }
}

void _entry(SendPort ready) {
  final commands = ReceivePort();
  Uint8List? frame;
  ready.send(commands.sendPort);
  commands.listen((dynamic message) {
    final reply = message[0] as SendPort;
    try {
      if (message[1] != null) {
        frame = (message[1] as TransferableTypedData)
            .materialize()
            .asUint8List();
      }
      final timer = Stopwatch()..start();
      final tensor = prepareRotatedMoveNet((
        PoseCropRequest(frame!, message[2] as PersonBox, 1),
        message[3] as int,
      ));
      reply.send([
        TransferableTypedData.fromList([tensor]),
        timer.elapsedMicroseconds,
      ]);
    } catch (error) {
      reply.send(['$error']);
    }
  });
}
