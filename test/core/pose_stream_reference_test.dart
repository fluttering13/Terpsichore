import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/pose_alignment.dart';
import 'package:terpsichore/core/ab_analysis/pose_post_processing.dart';

void main() {
  final data =
      jsonDecode(
            File('test/fixtures/pose_stream_reference.json').readAsStringSync(),
          )
          as Map;
  for (final row in data['fixtures'] as List) {
    test(
      '${row['backend']} ${row['case']} recorded stream search regression',
      () {
        final choreo = row['case'] == 'choreo';
        PoseSequence track(int index) => PoseSequence(
          ((row['tracks'][index]['frames']) as List)
              .map(
                (f) => PoseFrame(
                  (f['t'] as num).toDouble(),
                  (f['points'] as List)
                      .map(
                        (p) => PosePoint(
                          (p[0] as num).toDouble(),
                          (p[1] as num).toDouble(),
                          (p[2] as num).toDouble(),
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
          choreo ? (index == 0 ? 484 / 640 : 398 / 620) : 9 / 16,
        );
        final result = solveThunderAlignment(
          PoseAlignmentRequest(
            a: medianPoseSequence(track(0), .5),
            b: medianPoseSequence(track(1), .5),
            aStart: 0,
            aEnd: choreo ? 5.7 : 1.3,
            aRate: choreo ? 1 : .35,
            bStart: choreo ? .6 : 0,
            bEnd: choreo ? 7.249 : 4.245,
            bAnchorStart: choreo ? 1.2 : 0,
            bAnchorEnd: choreo ? 7.2 : 4.2,
          ),
        );
        expect(result, isNotNull);
        expect(
          result!.bStart,
          closeTo(row['expected']['b_start'] as num, .011),
        );
        expect(result.bRate, closeTo(row['expected']['b_rate'] as num, .006));
        expect(result.coverage, greaterThanOrEqualTo(.6));
      },
    );
  }
}
