import 'package:video_player/video_player.dart';

import '../../core/shared_video_playback/video_source.dart';
import 'local_video_controller_io.dart'
    if (dart.library.js_interop) 'local_video_controller_web.dart'
    as implementation;

VideoPlayerController createLocalVideoController(
  VideoSource source, {
  VideoPlayerOptions? videoPlayerOptions,
}) => implementation.createLocalVideoController(
  source,
  videoPlayerOptions: videoPlayerOptions,
);
