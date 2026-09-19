// Run on an Android device with the saved analysis project "bug1".
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:terpsichore/infrastructure/video_playback/video_playback_ready.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = await getApplicationDocumentsDirectory();
  final projects =
      jsonDecode(
            await File(
              '${root.path}/saved_projects/projects.json',
            ).readAsString(),
          )
          as List;
  final data = projects.firstWhere((p) => p['name'] == 'bug1')['data'];
  final players = <VideoPlayerController>[];
  for (final key in ['trackA', 'trackB']) {
    final track = data[key];
    final player = VideoPlayerController.file(
      File(track['source']['path'] as String),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await player.initialize();
    await player.setPlaybackSpeed((track['rate'] as num).toDouble());
    await player.setVolume(key == 'trackA' ? 1 : 0);
    players.add(player);
  }
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            for (final player in players)
              Expanded(
                child: AspectRatio(
                  aspectRatio: player.value.aspectRatio,
                  child: VideoPlayer(player),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  final watch = Stopwatch()..start();
  for (var i = 0; i < players.length; i++) {
    String? previous;
    players[i].addListener(() {
      final v = players[i].value;
      final state = '${v.isPlaying}/${v.isBuffering}';
      if (state != previous) {
        debugPrint(
          'AB_START ${watch.elapsedMilliseconds} $i $state pos=${v.position.inMilliseconds}',
        );
        previous = state;
      }
    });
  }
  for (var attempt = 0; attempt < 12; attempt++) {
    await Future.wait(players.map((p) => p.pause()));
    debugPrint(
      'AB_START seek attempt=$attempt at=${watch.elapsedMilliseconds}',
    );
    await Future.wait([
      players[0].seekTo(const Duration(milliseconds: 6104)),
      players[1].seekTo(const Duration(milliseconds: 5740)),
    ]);
    debugPrint('AB_START play at=${watch.elapsedMilliseconds}');
    await startVideoPlaybackTogether(players, isActive: () => true);
    await Future<void>.delayed(const Duration(seconds: 1));
    final positions = await Future.wait(players.map((p) => p.position));
    if (positions[0]! <= const Duration(milliseconds: 6204) ||
        positions[1]! <= const Duration(milliseconds: 5778)) {
      throw StateError('A or B did not advance: $positions');
    }
    debugPrint('AB_START verified attempt=$attempt positions=$positions');
  }
  await Future.wait(players.map((p) => p.pause()));
  debugPrint('AB_START complete');
}
