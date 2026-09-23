import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/ab_analysis/analysis_project.dart';
import 'package:terpsichore/core/shared_video_playback/playback_rate.dart';
import 'package:terpsichore/core/shared_video_playback/time_range.dart';
import 'package:terpsichore/core/shared_video_playback/video_source.dart';
import 'package:terpsichore/entrypoints/mobile/screens/analysis_export_preview_screen.dart';
import 'package:video_player/video_player.dart';

void main() {
  late VideoPlayerController a;
  late VideoPlayerController b;
  bool? result;
  int toggles = 0;
  final seeks = <double>[];

  AnalysisTrack track(String id, double rate) => AnalysisTrack(
    source: VideoSource(id: id, path: '/$id.mp4', label: id),
    mediaDuration: const Duration(seconds: 30),
    trim: TimeRange(
      start: const Duration(seconds: 5),
      end: const Duration(seconds: 15),
    ),
    rate: PlaybackRate(rate),
  );

  setUp(() {
    a = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/a.mp4'),
    );
    b = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/b.mp4'),
    );
    for (final player in [a, b]) {
      player.value = const VideoPlayerValue(
        duration: Duration(seconds: 30),
        position: Duration(seconds: 5),
        size: Size(1280, 720),
        isInitialized: true,
      );
    }
    result = null;
    toggles = 0;
    seeks.clear();
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  Future<void> open(
    WidgetTester tester, {
    AnalysisOutput output = AnalysisOutput.sideBySide,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => AnalysisExportPreviewScreen(
                      project: AnalysisProject(
                        trackA: track('a', 2),
                        trackB: track('b', 0.5),
                        output: output,
                      ),
                      playerA: a,
                      playerB: b,
                      onToggle: () async {
                        toggles++;
                      },
                      onSeekStart: (_) async {},
                      onSeek: (value) async {
                        seeks.add(value);
                      },
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('immediately displays existing players and confirms explicitly', (
    tester,
  ) async {
    await open(tester);
    final players = tester
        .widgetList<VideoPlayer>(find.byType(VideoPlayer))
        .toList();
    expect(players.map((p) => p.controller), [a, b]);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(result, isNull);
    await tester.tap(find.byTooltip('播放預覽'));
    await tester.pumpAndSettle();
    expect(toggles, 1);
    await tester.tap(find.text('確認輸出'));
    await tester.pumpAndSettle();
    expect(result, true);
    // The route must not dispose the editor's players.
    a.value = a.value.copyWith(position: const Duration(seconds: 6));
    expect(a.value.isInitialized, isTrue);
  });

  testWidgets('returning does not confirm export', (tester) async {
    await open(tester);
    await tester.tap(find.text('回到上一步'));
    await tester.pumpAndSettle();
    expect(result, false);
  });

  testWidgets('B-only uses B trim, speed and full duration for progress', (
    tester,
  ) async {
    b.value = b.value.copyWith(position: const Duration(seconds: 10));
    await open(tester, output: AnalysisOutput.trackBOnly);
    expect(tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller, b);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.5);
    await tester.tap(find.byType(Slider));
    await tester.pumpAndSettle();
    expect(seeks, isNotEmpty);
  });

  testWidgets('playback error disables confirmation and allows returning', (
    tester,
  ) async {
    await open(tester);
    b.value = b.value.copyWith(errorDescription: 'playback failed');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('回到上一步'));
    await tester.pumpAndSettle();
    expect(result, false);
  });
}
