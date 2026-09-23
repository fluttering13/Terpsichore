import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/infrastructure/media/same_video.dart';

void main() {
  test(
    'matches remuxed media by stream fingerprint, not container bytes',
    () async {
      final calls = <String>[];
      Future<String?> fingerprint(String path) async {
        calls.add(path);
        return '0,v,SHA256=same-video\n1,a,SHA256=same-audio';
      }

      expect(
        await isSameVideo(
          '/first-copy.mkv',
          '/second-copy.mkv',
          fingerprint: fingerprint,
        ),
        isTrue,
      );
      expect(calls, ['/first-copy.mkv', '/second-copy.mkv']);
      expect(
        await isSameVideo(
          '/first.mkv',
          '/other.mkv',
          fingerprint: (path) async => path,
        ),
        isFalse,
      );
      expect(
        await isSameVideo(
          '/first.mkv',
          '/other.mkv',
          fingerprint: (_) async => null,
        ),
        isFalse,
      );
    },
  );
  test(
    'recognizes cache copies, but rejects same-name or same-size differences',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'same-video-test-',
      );
      try {
        final a = File('${directory.path}/a.mp4');
        final b = File('${directory.path}/b.mp4');
        final data = List<int>.generate(150000, (i) => i % 251);
        await a.writeAsBytes(data);
        await b.writeAsBytes(data);
        expect(await isSameVideo(a.path, a.path), isTrue);
        expect(await isSameVideo(a.path, b.path), isTrue);
        data[100000] ^= 1;
        await b.writeAsBytes(data);
        expect(await isSameVideo(a.path, b.path), isFalse);
        await b.writeAsBytes([1, 2, 3]);
        expect(await isSameVideo(a.path, b.path), isFalse);
        await b.delete();
        expect(await isSameVideo(a.path, b.path), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
