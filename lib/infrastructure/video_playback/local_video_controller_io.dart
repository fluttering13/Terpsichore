import 'dart:io';

import 'package:video_player/video_player.dart';

import '../../core/shared_video_playback/video_source.dart';

VideoPlayerController createLocalVideoController(
  VideoSource source, {
  VideoPlayerOptions? videoPlayerOptions,
}) => VideoPlayerController.file(
  File(source.path),
  videoPlayerOptions: videoPlayerOptions,
);
