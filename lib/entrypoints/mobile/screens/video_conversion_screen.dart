import 'package:terpsichore/infrastructure/engagement/easter_egg_service.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/ab_analysis/analysis_gallery.dart';
import '../../../core/shared_video_playback/video_source.dart';
import '../../../core/video_conversion/video_conversion.dart';
import '../../../infrastructure/analysis/device_analysis_gallery.dart';
import '../../../infrastructure/media/local_video_picker.dart';
import '../../../infrastructure/video_conversion/ffmpeg_video_converter.dart';
import '../../../infrastructure/video_playback/local_video_controller.dart';

final class VideoConversionScreen extends StatefulWidget {
  const VideoConversionScreen({super.key});

  @override
  State<VideoConversionScreen> createState() => _VideoConversionScreenState();
}

final class _VideoConversionScreenState extends State<VideoConversionScreen> {
  static const _picker = LocalVideoPicker();
  static const VideoConverter _converter = FfmpegVideoConverter();
  static const _gallery = DeviceAnalysisGallery();

  VideoSource? _source;
  VideoMediaInfo? _mediaInfo;
  VideoOutputFormat _outputFormat = VideoOutputFormat.mp4;
  VideoQuality _quality = VideoQuality.balanced;
  VideoResolution _resolution = VideoResolution.p1080;
  VideoCodec _codec = VideoCodec.h264;
  VideoPlayerController? _preview;
  int? _inputBytes;
  int? _outputBytes;
  bool _inspecting = false;
  bool _converting = false;
  bool _savedToGallery = false;
  double _conversionProgress = 0;
  Duration _processedDuration = Duration.zero;
  bool _savingConvertedVideo = false;
  String? _outputPath;
  String? _error;

  Future<void> _pickVideo() async {
    if (_inspecting || _converting) return;
    final source = await _picker.pick();
    if (source == null) return;
    setState(() {
      _source = source;
      _mediaInfo = null;
      _outputPath = null;
      _savedToGallery = false;
      _inputBytes = null;
      _outputBytes = null;
      _error = null;
      _conversionProgress = 0;
      _processedDuration = Duration.zero;
      _savingConvertedVideo = false;
      _inspecting = true;
    });
    final oldPreview = _preview;
    _preview = null;
    await oldPreview?.dispose();
    VideoPlayerController? preview;
    var previewReady = false;
    try {
      preview = createLocalVideoController(source);
      try {
        await preview.initialize();
        previewReady = true;
      } catch (_) {
        await preview.dispose();
      }
      final info = await _converter.inspect(source.path);
      if (!mounted || _source?.id != source.id) return;
      final size = await File(source.path).length();
      if (!mounted || _source?.id != source.id) return;
      setState(() {
        _mediaInfo = info;
        _inputBytes = size;
        _codec = _outputFormat == VideoOutputFormat.avi
            ? VideoCodec.mpeg4
            : _resolution.recommendedCodec(info);
        if (previewReady) _preview = preview;
      });
    } catch (error) {
      if (previewReady) await preview?.dispose();
      if (!mounted || _source?.id != source.id) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted && _source?.id == source.id) {
        setState(() => _inspecting = false);
      }
    }
  }

  Future<void> _convert() async {
    final source = _source;
    if (source == null || _mediaInfo == null || _converting) return;
    setState(() {
      _converting = true;
      _outputPath = null;
      _outputBytes = null;
      _savedToGallery = false;
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在轉換影片，時間依影片長度而定，請保持 App 開啟…')),
    );
    try {
      final result = await _converter.convert(
        inputPath: source.path,
        outputFormat: _outputFormat,
        quality: _quality,
        codec: _codec,
        resolution: _resolution,
        inputDuration: _mediaInfo?.duration,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _conversionProgress = progress.fraction;
            _processedDuration = progress.processed;
          });
        },
      );
      if (!mounted) return;
      switch (result) {
        case VideoConversionSucceeded(:final path):
          EasterEggService.instance.exportCompleted();
          final outputBytes = await File(path).length();
          if (!mounted) return;
          setState(() {
            _outputPath = path;
            _outputBytes = outputBytes;
            _conversionProgress = 1;
            _savingConvertedVideo = true;
          });
          await _saveToGallery();
        case VideoConversionFailed(:final reason):
          setState(() => _error = reason);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _converting = false;
          _savingConvertedVideo = false;
        });
      }
    }
  }

  Future<void> _saveToGallery() async {
    final path = _outputPath;
    if (path == null) return;
    final result = await _gallery.save(
      path,
      folder: AnalysisGalleryFolder.defaultFolder,
    );
    if (!mounted) return;
    final message = switch (result) {
      AnalysisSavedToGallery() => '已儲存至裝置媒體庫的 Terpsichore 相簿',
      AnalysisGallerySaveFailed(:final reason) => '無法儲存至媒體庫：$reason',
    };
    setState(() => _savedToGallery = result is AnalysisSavedToGallery);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share() async {
    final path = _outputPath;
    if (path == null) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: _outputFormat.mimeType)],
        title: 'Terpsichore 影片轉檔',
        text: 'Terpsichore 轉換後的 ${_outputFormat.label} 影片',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: false,
          title: const Text('影片轉檔'),
          actions: [
            TextButton.icon(
              onPressed: _converting || _inspecting ? null : _pickVideo,
              icon: const Icon(Icons.video_file_outlined),
              label: Text(_source == null ? '選擇影片' : '更換影片'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: [
              _SourceCard(
                source: _source,
                mediaInfo: _mediaInfo,
                inspecting: _inspecting,
                preview: _preview,
                inputBytes: _inputBytes,
                onPick: _pickVideo,
                onTogglePreview: () async {
                  final preview = _preview;
                  if (preview == null) return;
                  if (preview.value.isPlaying) {
                    await preview.pause();
                  } else {
                    if (preview.value.position >= preview.value.duration) {
                      await preview.seekTo(Duration.zero);
                    }
                    await preview.play();
                  }
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 16),
              _OutputCard(
                value: _outputFormat,
                quality: _quality,
                resolution: _resolution,
                codec: _codec,
                mediaInfo: _mediaInfo,
                enabled: !_converting,
                onChanged: (value) => setState(() {
                  _outputFormat = value;
                  if (value == VideoOutputFormat.avi) {
                    _codec = VideoCodec.mpeg4;
                    if (_resolution == VideoResolution.original ||
                        _resolution == VideoResolution.p2160) {
                      _resolution = VideoResolution.p1080;
                    }
                  } else {
                    _codec = _resolution.recommendedCodec(_mediaInfo);
                  }
                  _outputPath = null;
                  _outputBytes = null;
                  _savedToGallery = false;
                }),
                onResolutionChanged: (value) => setState(() {
                  _resolution = value;
                  _codec = _outputFormat == VideoOutputFormat.avi
                      ? VideoCodec.mpeg4
                      : value.recommendedCodec(_mediaInfo);
                  _outputPath = null;
                  _outputBytes = null;
                  _savedToGallery = false;
                }),
                onCodecChanged: (value) => setState(() {
                  _codec = value;
                  _outputPath = null;
                  _outputBytes = null;
                  _savedToGallery = false;
                }),
                onQualityChanged: (value) => setState(() {
                  _quality = value;
                  _outputPath = null;
                  _outputBytes = null;
                  _savedToGallery = false;
                }),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline),
                        const SizedBox(width: 10),
                        Expanded(child: Text(error)),
                      ],
                    ),
                  ),
                ),
              ],
              if (_converting) ...[
                const SizedBox(height: 16),
                _ConversionProgressCard(
                  progress: _conversionProgress,
                  processed: _processedDuration,
                  total: _mediaInfo?.duration,
                  savingToGallery: _savingConvertedVideo,
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _mediaInfo != null && !_converting ? _convert : null,
                icon: _converting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  _converting ? '正在轉檔…' : '轉換成 ${_outputFormat.label}',
                ),
              ),
              if (_outputPath != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.greenAccent),
                            SizedBox(width: 8),
                            Text('轉檔完成'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_outputBytes case final bytes?) ...[
                          Text(
                            '輸出大小：${_fileSize(bytes)}'
                            '${_inputBytes == null ? '' : '（原始 ${_fileSize(_inputBytes!)}）'}',
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          _savedToGallery ? '已自動儲存至媒體庫' : '自動儲存失敗，可按下方按鈕重試。',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (!_savedToGallery)
                              FilledButton.tonalIcon(
                                onPressed: _saveToGallery,
                                icon: const Icon(Icons.save_alt),
                                label: const Text('重試儲存'),
                              ),
                            OutlinedButton.icon(
                              onPressed: _share,
                              icon: const Icon(Icons.share_outlined),
                              label: const Text('分享／另存'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst('FormatException: ', '')
      .replaceFirst('Bad state: ', '');
}

final class _ConversionProgressCard extends StatelessWidget {
  const _ConversionProgressCard({
    required this.progress,
    required this.processed,
    required this.total,
    required this.savingToGallery,
  });

  final double progress;
  final Duration processed;
  final Duration? total;
  final bool savingToGallery;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round().clamp(0, 100);
    final totalDuration = total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  savingToGallery
                      ? Icons.save_alt_outlined
                      : Icons.movie_filter_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    savingToGallery ? '轉檔完成，正在儲存至媒體庫…' : '影片轉檔進度',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '$percent%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              borderRadius: BorderRadius.circular(20),
            ),
            if (!savingToGallery && totalDuration != null) ...[
              const SizedBox(height: 8),
              Text(
                '已處理 ${_duration(processed)} / ${_duration(totalDuration)}',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.mediaInfo,
    required this.inspecting,
    required this.preview,
    required this.inputBytes,
    required this.onPick,
    required this.onTogglePreview,
  });

  final VideoSource? source;
  final VideoMediaInfo? mediaInfo;
  final bool inspecting;
  final VideoPlayerController? preview;
  final int? inputBytes;
  final VoidCallback onPick;
  final VoidCallback onTogglePreview;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: source == null
          ? Column(
              children: [
                Icon(
                  Icons.movie_creation_outlined,
                  size: 58,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  '選擇要轉換的影片',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text('輸入格式會自動偵測，支援 MOV、MP4、MKV、AVI 等常見影片。'),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: onPick,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('選擇影片'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (preview != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: preview!.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: Colors.black,
                            child: VideoPlayer(preview!),
                          ),
                          Center(
                            child: IconButton.filledTonal(
                              onPressed: onTogglePreview,
                              iconSize: 34,
                              icon: Icon(
                                preview!.value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    const Icon(Icons.movie_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        source!.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 26),
                if (inspecting)
                  const Row(
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('正在自動偵測輸入格式…'),
                    ],
                  )
                else if (mediaInfo case final info?)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(label: '格式', value: info.container),
                      if (info.videoCodec case final codec?)
                        _InfoChip(label: '影像', value: codec),
                      if (info.audioCodec case final codec?)
                        _InfoChip(label: '聲音', value: codec),
                      if (info.width case final width?)
                        _InfoChip(
                          label: '解析度',
                          value: '$width × ${info.height ?? '?'}',
                        ),
                      if (info.duration case final duration?)
                        _InfoChip(label: '長度', value: _duration(duration)),
                      if (inputBytes case final bytes?)
                        _InfoChip(label: '上傳大小', value: _fileSize(bytes)),
                    ],
                  ),
              ],
            ),
    ),
  );
}

final class _OutputCard extends StatelessWidget {
  const _OutputCard({
    required this.value,
    required this.quality,
    required this.resolution,
    required this.codec,
    required this.mediaInfo,
    required this.enabled,
    required this.onChanged,
    required this.onResolutionChanged,
    required this.onCodecChanged,
    required this.onQualityChanged,
  });

  final VideoOutputFormat value;
  final VideoQuality quality;
  final VideoResolution resolution;
  final VideoCodec codec;
  final VideoMediaInfo? mediaInfo;
  final bool enabled;
  final ValueChanged<VideoOutputFormat> onChanged;
  final ValueChanged<VideoResolution> onResolutionChanged;
  final ValueChanged<VideoCodec> onCodecChanged;
  final ValueChanged<VideoQuality> onQualityChanged;

  @override
  Widget build(BuildContext context) {
    final recommendedCodec = resolution.recommendedCodec(mediaInfo);
    final dimensions = resolution.outputDimensions(mediaInfo);
    final matchesRecommendation = codec == recommendedCodec;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('輸出格式', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('MP4 相容性最佳；MOV 適合 Apple 裝置與剪輯軟體。'),
            const SizedBox(height: 14),
            DropdownButtonFormField<VideoOutputFormat>(
              initialValue: value,
              decoration: const InputDecoration(
                labelText: '轉換成',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.output),
              ),
              items: VideoOutputFormat.values
                  .map(
                    (format) => DropdownMenuItem(
                      value: format,
                      child: Text('${format.label} (.${format.extension})'),
                    ),
                  )
                  .toList(),
              onChanged: enabled
                  ? (format) {
                      if (format != null) onChanged(format);
                    }
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<VideoResolution>(
              initialValue: resolution,
              decoration: const InputDecoration(
                labelText: '輸出解析度',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.aspect_ratio_outlined),
              ),
              items: VideoResolution.values
                  .where(
                    (item) =>
                        value != VideoOutputFormat.avi ||
                        item == VideoResolution.p720 ||
                        item == VideoResolution.p1080,
                  )
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item, child: Text(item.label)),
                  )
                  .toList(),
              onChanged: enabled
                  ? (newResolution) {
                      if (newResolution != null) {
                        onResolutionChanged(newResolution);
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<VideoCodec>(
              initialValue: codec,
              decoration: const InputDecoration(
                labelText: '影像編碼',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.memory_outlined),
              ),
              items: value.supportedCodecs
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item, child: Text(item.label)),
                  )
                  .toList(),
              onChanged: enabled
                  ? (newCodec) {
                      if (newCodec != null) onCodecChanged(newCodec);
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              '${dimensions == null ? '' : '預計 ${dimensions.width} × ${dimensions.height} · '}'
              '${codec.description}${matchesRecommendation ? '（建議）' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: matchesRecommendation
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
            ),
            if (!matchesRecommendation) ...[
              const SizedBox(height: 4),
              Text(
                '${resolution.label} 建議使用 ${recommendedCodec.label}。',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<VideoQuality>(
              initialValue: quality,
              decoration: const InputDecoration(
                labelText: '輸出畫質',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.high_quality_outlined),
              ),
              items: VideoQuality.values
                  .map(
                    (preset) => DropdownMenuItem(
                      value: preset,
                      child: Text('${preset.label}｜${preset.description}'),
                    ),
                  )
                  .toList(),
              onChanged: enabled
                  ? (preset) {
                      if (preset != null) onQualityChanged(preset);
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

final class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      Chip(label: Text('$label：$value'), visualDensity: VisualDensity.compact);
}

String _duration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(1)} KB';
  final megabytes = kilobytes / 1024;
  if (megabytes < 1024) return '${megabytes.toStringAsFixed(1)} MB';
  return '${(megabytes / 1024).toStringAsFixed(2)} GB';
}
