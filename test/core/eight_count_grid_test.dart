import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/learning_mode/eight_count_grid.dart';

void main() {
  group('EightCountGrid', () {
    final grid = EightCountGrid(
      firstEightStart: Duration(seconds: 10),
      firstEightEnd: Duration(seconds: 14),
    );

    test('derives beat length from one complete eight', () {
      expect(grid.beatLength, const Duration(milliseconds: 500));
    });

    test('maps time to one-based eight and beat', () {
      expect(
        grid.positionAt(const Duration(seconds: 10))?.label,
        '第 1 個八・第 1 拍',
      );
      expect(
        grid.positionAt(const Duration(milliseconds: 13500))?.label,
        '第 1 個八・第 8 拍',
      );
      expect(
        grid.positionAt(const Duration(seconds: 14))?.label,
        '第 2 個八・第 1 拍',
      );
    });

    test('has no count before the calibrated start', () {
      expect(grid.positionAt(const Duration(milliseconds: 9999)), isNull);
    });

    test('maps an inclusive eight range to a fine-tunable time range', () {
      final oneEight = grid.rangeForEights(
        startEight: 1,
        endEight: 1,
        mediaDuration: const Duration(seconds: 30),
      );
      final twoEights = grid.rangeForEights(
        startEight: 1,
        endEight: 2,
        mediaDuration: const Duration(seconds: 30),
      );

      expect(oneEight.start, const Duration(seconds: 10));
      expect(oneEight.end, const Duration(seconds: 14));
      expect(twoEights.start, const Duration(seconds: 10));
      expect(twoEights.end, const Duration(seconds: 18));
    });

    test('counts and clamps a partial last eight to the video end', () {
      expect(grid.availableEightCount(const Duration(seconds: 19)), 3);
      final range = grid.rangeForEights(
        startEight: 3,
        endEight: 3,
        mediaDuration: const Duration(seconds: 19),
      );
      expect(range.start, const Duration(seconds: 18));
      expect(range.end, const Duration(seconds: 19));
    });
  });
}
