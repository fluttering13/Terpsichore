import 'dart:async';
import '../../../infrastructure/engagement/easter_egg_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/platform_download/platform_video.dart';
import '../../../infrastructure/platform_download/native_platform_video_downloader.dart';
import '../../../infrastructure/platform_download/instagram_session.dart';
import '../../../infrastructure/engagement/emotion_backmail_service.dart';

final class PlatformVideoDownloadScreen extends StatefulWidget {
  const PlatformVideoDownloadScreen({
    this.downloader = const NativePlatformVideoDownloader(),
    this.instagramSession = const NativeInstagramSession(),
    super.key,
  });
  final PlatformVideoDownloader downloader;
  final InstagramSession instagramSession;

  @override
  State<PlatformVideoDownloadScreen> createState() =>
      _PlatformVideoDownloadScreenState();
}

final class _PlatformVideoDownloadScreenState
    extends State<PlatformVideoDownloadScreen> {
  final _link = TextEditingController();
  StreamSubscription<DownloadProgress>? _subscription;
  PlatformVideo? _video;
  PlatformVideoFormat? _format;
  final _selected = <String, PlatformVideoFormat>{};
  bool _combine = false;
  int _item = 0, _total = 0;
  DownloadPlatform? _platform;
  DownloadReceipt? _receipt;
  DownloadException? _error;
  String? _jobId;
  String _phase = 'inspecting';
  double? _fraction;
  bool _inspecting = false;
  static const _phaseOrder = {
    'initializing': 0,
    'inspecting': 1,
    'connecting': 1,
    'metadata': 2,
    'formats': 3,
    'downloading': 4,
    'audio': 5,
    'merging': 6,
    'saving': 7,
  };
  bool _cancelling = false;
  bool _authenticating = false;
  int _sequence = 0;
  bool get _busy => _jobId != null || _authenticating;

  Future<bool> _chooseInstagramLogin() async {
    final en = EmotionBackmailService.language.value == AppLanguage.english;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(en ? 'Instagram sign-in required' : '需要 Instagram 登入狀態'),
        content: Text(
          en
              ? 'Use an account that can view this story. Sign in on Instagram’s webpage, or import a Netscape cookies.txt file. The session is stored only on this phone; you can clear it below.'
              : '請使用能觀看此限動的帳號。可在 Instagram 網頁登入，或匯入瀏覽器匯出的 Netscape cookies.txt。登入狀態只儲存在此手機，可隨時清除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(en ? 'Cancel' : '取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'import'),
            child: Text(en ? 'Import session' : '匯入登入狀態'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'login'),
            child: Text(en ? 'Sign in to Instagram' : '登入 Instagram'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return false;
    return widget.instagramSession.authenticate(
      importFile: choice == 'import',
      english: en,
    );
  }

  Future<void> _manageInstagram({bool clear = false}) async {
    if (_busy) return;
    setState(() => _authenticating = true);
    var retry = false;
    try {
      if (clear) {
        await widget.instagramSession.clear();
        if (mounted) {
          setState(() {
            _video = null;
            _format = null;
            _error = null;
          });
          final en =
              EmotionBackmailService.language.value == AppLanguage.english;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                en ? 'Instagram session cleared.' : '已清除 Instagram 登入狀態。',
              ),
            ),
          );
        }
      } else {
        retry = await _chooseInstagramLogin();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is DownloadException
              ? error
              : const DownloadException('IG_LOGIN_UNAVAILABLE'),
        );
      }
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
    if (mounted && retry) await _inspect();
  }

  void _listenForProgress() {
    _subscription ??= widget.downloader.progress.listen(
      (progress) {
        if (!mounted || progress.jobId != _jobId) return;
        setState(() {
          _item = progress.item;
          _total = progress.total;
          if (progress.total > 0 ||
              (_phaseOrder[progress.phase] ?? -1) >=
                  (_phaseOrder[_phase] ?? 0)) {
            _phase = progress.phase;
          }
          final fraction = progress.fraction;
          if (!_inspecting &&
              fraction != null &&
              fraction.isFinite &&
              fraction >= 0 &&
              fraction > (_fraction ?? 0)) {
            _fraction = fraction.clamp(0.0, 0.99);
          }
        });
      },
      onError: (Object _) {
        /* Method result remains authoritative. */
      },
    );
  }

  void _notifyInstagramError() {
    final error = _error;
    if (error == null || !error.code.startsWith('IG_')) return;
    final en = EmotionBackmailService.language.value == AppLanguage.english;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.message(en)),
        showCloseIcon: true,
        duration: const Duration(seconds: 10),
      ),
    );
  }

  @override
  void dispose() {
    final job = _jobId;
    if (job != null) {
      unawaited(widget.downloader.cancel(job).catchError((Object _) {}));
    }
    _subscription?.cancel();
    _link.dispose();
    super.dispose();
  }

  void _clearPreview() {
    setState(() {
      _video = null;
      _format = null;
      _platform = null;
      _receipt = null;
      _error = null;
      _selected.clear();
    });
  }

  Future<void> _paste() async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || _busy) return;
      _link.text = clipboard?.text ?? '';
      _clearPreview();
      if (_link.text.trim().isNotEmpty) await _inspect();
    } catch (_) {
      if (mounted) {
        setState(() => _error = const DownloadException('INVALID_URL'));
      }
    }
  }

  String _start(String phase) {
    _listenForProgress();
    final id = '${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';
    setState(() {
      _jobId = id;
      _inspecting = phase == 'inspecting';
      _phase = 'initializing';
      _fraction = _inspecting ? null : 0;
      _error = null;
      _receipt = null;
      _cancelling = false;
      _item = 0;
      _total = 0;
    });
    return id;
  }

  Future<void> _inspect() async {
    if (_busy) return;
    _clearPreview();
    try {
      final link = PlatformVideoLink.parse(_link.text);
      setState(() => _platform = link.platform);
      if (link.isInstagramStory) {
        setState(() => _authenticating = true);
        final hasSession = await widget.instagramSession.hasSession();
        if (!mounted) return;
        if (!hasSession && !await _chooseInstagramLogin()) return;
        if (!mounted) return;
        setState(() => _authenticating = false);
      }
      final id = _start('inspecting');
      _platform = link.platform;
      final video = await widget.downloader.inspect(link.uri.toString(), id);
      if (!mounted) return;
      if (_cancelling) throw const DownloadException('CANCELLED');
      if (video.formats.isEmpty) throw const DownloadException('NO_VIDEO');
      setState(() {
        _video = video;
        _format = video.formats.first;
        _selected.clear();
        for (final entry in video.entries) {
          if (entry.formats.isNotEmpty) {
            _selected[entry.snapshotId] = _preferred(entry);
          }
        }
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is DownloadException
              ? error
              : const DownloadException('EXTRACTION_FAILED'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _jobId = null;
          _cancelling = false;
          _authenticating = false;
        });
        _notifyInstagramError();
      }
    }
  }

  Future<void> _download() async {
    if (_busy || _video == null || _format == null) return;
    final entries = _video!.entries
        .where((entry) => _selected.containsKey(entry.snapshotId))
        .toList();
    if (_video!.entries.isNotEmpty && entries.isEmpty) return;
    final platform = _platform;
    final id = _start('downloading');
    try {
      final receipt = _video!.entries.isEmpty
          ? await widget.downloader.download(_video!, _format!, id)
          : await widget.downloader.downloadSelection(
              entries,
              entries.map((entry) => _selected[entry.snapshotId]!).toList(),
              id,
              combine: _combine,
            );
      if (platform != null && receipt.location.isNotEmpty) {
        EasterEggService.instance.downloadCompleted(platform);
      }
      if (mounted) {
        setState(() {
          _receipt = receipt;
          for (final issue in receipt.issues) {
            final code = issue.split(':').last;
            if (code.startsWith('IG_')) {
              _error = DownloadException(code);
              break;
            }
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is DownloadException
              ? error
              : const DownloadException('DOWNLOAD_FAILED'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _jobId = null;
          _cancelling = false;
        });
        _notifyInstagramError();
      }
    }
  }

  Future<void> _cancel() async {
    final id = _jobId;
    if (id == null) return;
    setState(() => _cancelling = true);
    try {
      await widget.downloader.cancel(id);
    } catch (_) {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: EmotionBackmailService.language,
    builder: (context, language, _) {
      final en = language == AppLanguage.english;
      final video = _video;
      final receipt = _receipt;
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              en ? 'Platform video download' : '平台影片下載',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('YouTube · Instagram · Facebook · Threads'),
            const SizedBox(height: 16),
            Text(
              en
                  ? 'Paste a video link to check access and available quality before downloading.'
                  : '貼上影片連結，先確認存取權限及可用畫質，再下載到本機。',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('platform-video-link'),
              controller: _link,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                labelText: en ? 'Video link' : '影片連結',
                hintText: 'https://…',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _clearPreview(),
              onSubmitted: (_) => _inspect(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _paste,
                  icon: const Icon(Icons.content_paste),
                  label: Text(en ? 'Paste link' : '貼上連結'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _inspect,
                  icon: const Icon(Icons.search),
                  label: Text(en ? 'Analyze video' : '解析影片'),
                ),
              ],
            ),
            if (_platform == DownloadPlatform.instagram)
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : () => _manageInstagram(),
                    icon: const Icon(Icons.login),
                    label: Text(en ? 'Sign in / import session' : '登入／匯入登入狀態'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _manageInstagram(clear: true),
                    child: Text(en ? 'Clear Instagram session' : '清除 IG 登入狀態'),
                  ),
                ],
              ),
            if (_authenticating) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              Text(
                en ? 'Waiting for Instagram sign-in…' : '正在等待 Instagram 登入…',
              ),
            ],
            if (_jobId != null) ...[
              const SizedBox(height: 20),
              if (_inspecting)
                const LinearProgressIndicator()
              else
                TweenAnimationBuilder<double>(
                  key: ValueKey(_jobId),
                  tween: Tween(begin: 0, end: _fraction ?? 0),
                  duration: const Duration(milliseconds: 250),
                  builder: (context, value, _) =>
                      LinearProgressIndicator(value: value),
                ),
              const SizedBox(height: 8),
              if (_total > 0)
                Text(en ? 'Video $_item / $_total' : '第 $_item／$_total 支影片'),
              Text(
                _cancelling
                    ? (en ? 'Cancelling…' : '正在取消…')
                    : switch (_phase) {
                        'initializing' =>
                          en ? 'Preparing video service…' : '正在準備影片服務…',
                        'connecting' =>
                          en
                              ? 'Connecting to the video platform…'
                              : '正在連線至影片平台…',
                        'metadata' =>
                          en
                              ? 'Reading video and audio information…'
                              : '正在讀取影片與音軌資料…',
                        'formats' =>
                          en
                              ? 'Checking available quality…'
                              : '正在整理可下載的畫質與解析度…',
                        'inspecting' =>
                          en
                              ? 'Checking video access and quality…'
                              : '正在確認影片存取權限與畫質…',
                        'saving' => en ? 'Saving to this device…' : '正在儲存到本機…',
                        'verifying' =>
                          en ? 'Checking downloaded audio…' : '正在檢查下載檔案的音軌…',
                        'combining' =>
                          en ? 'Combining selected videos…' : '正在合成選取的影片…',
                        'audio' => en ? 'Downloading audio…' : '正在下載音軌…',
                        'merging' =>
                          en ? 'Merging video and audio…' : '正在合併影片與音軌…',
                        _ => en ? 'Downloading video…' : '正在下載影片…',
                      },
              ),
              if (!_inspecting)
                Text(
                  en
                      ? 'Overall progress ${((_fraction ?? 0) * 100).floor()}%'
                      : '整體進度 ${((_fraction ?? 0) * 100).floor()}%',
                ),
              Text(
                en
                    ? 'Keep the app open until the download finishes.'
                    : '下載完成前請保持 App 開啟。',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _cancelling ? null : _cancel,
                  child: Text(en ? 'Cancel' : '取消'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!.message(en),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (video != null) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _platform?.label ?? '',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ColoredBox(
                            color: Colors.black,
                            child: video.thumbnailUrl == null
                                ? _thumbnailUnavailable(en)
                                : Image.network(
                                    video.thumbnailUrl!,
                                    key: ValueKey(video.snapshotId),
                                    fit: BoxFit.contain,
                                    semanticLabel: en
                                        ? 'Video preview'
                                        : '影片預覽圖',
                                    loadingBuilder:
                                        (
                                          context,
                                          child,
                                          progress,
                                        ) => progress == null
                                        ? child
                                        : const Center(
                                            child: SizedBox.square(
                                              dimension: 28,
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                          ),
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            _thumbnailUnavailable(en),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        video.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (video.entries.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ..._selectionControls(video, en),
                      ],
                      if (video.firstVideoOnly && video.entries.isEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          en
                              ? 'This post contains multiple items; the first video is selected.'
                              : '此貼文有多個項目，本次下載第一支影片。',
                        ),
                      ],
                      if (video.entries.isEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          en ? 'Quality and resolution' : '畫質與解析度',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey(video.snapshotId),
                          initialValue: _format?.id,
                          isExpanded: true,
                          itemHeight: null,
                          selectedItemBuilder: (context) => video.formats
                              .map(
                                (format) => Text(
                                  format.label(en),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                              .toList(),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                          items: video.formats
                              .map(
                                (format) => DropdownMenuItem(
                                  value: format.id,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Text(format.label(en)),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (id) => setState(
                                  () => _format = video.formats.firstWhere(
                                    (format) => format.id == id,
                                  ),
                                ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        en
                            ? 'Only qualities provided by the source are listed. Some videos have one quality. Separate audio is merged automatically; size estimates may exclude audio.'
                            : '僅列出來源實際提供的畫質，部分影片只有一種。分離音軌會自動合併；預估大小可能不含音軌。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed:
                            _busy ||
                                (video.entries.isNotEmpty && _selected.isEmpty)
                            ? null
                            : _download,
                        icon: const Icon(Icons.download),
                        label: Text(
                          video.entries.isEmpty
                              ? (en ? 'Download to device' : '下載到本機')
                              : _combine
                              ? (en
                                    ? 'Combine ${_selected.length} videos'
                                    : '合成選取的 ${_selected.length} 支影片')
                              : (en
                                    ? 'Download ${_selected.length} videos'
                                    : '下載選取的 ${_selected.length} 支影片'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (receipt != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          receipt.issues.isEmpty
                              ? (en ? 'Download complete' : '下載完成')
                              : (en
                                    ? 'Download results — please review'
                                    : '下載結果：有項目需要確認'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(receipt.location),
                        for (final issue in receipt.issues)
                          Text(_issueMessage(issue, en)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );

  PlatformVideoFormat _preferred(PlatformVideo entry) =>
      entry.formats.firstWhere(
        (format) => !format.silent,
        orElse: () => entry.formats.first,
      );

  String _issueMessage(String issue, bool en) {
    final parts = issue.split(':');
    final page = parts.first;
    final code = parts.last;
    final message = switch (code) {
      'AUDIO_NOT_FOUND' =>
        en
            ? 'No audio track was obtained; the saved video may be silent.'
            : '未取得音軌，已儲存的影片可能沒有聲音。可登入後重新解析。',
      'AUDIO_MISSING' =>
        en
            ? 'Expected audio is missing; this video was not saved.'
            : '預期的音軌缺少，此影片未儲存。',
      'COMBINE_FAILED' =>
        en
            ? 'Unable to combine the selected videos. No combined file was saved.'
            : '影片合成失敗，未儲存合成檔案。',
      _ => DownloadException(code).message(en),
    };
    return page == '0'
        ? message
        : (en ? 'Page $page: $message' : '第 $page 頁：$message');
  }

  List<Widget> _selectionControls(PlatformVideo video, bool en) => [
    Text(
      en
          ? '${video.entries.length} videos · ${_selected.length} selected'
          : '找到 ${video.entries.length} 支影片・已選 ${_selected.length} 支',
    ),
    Wrap(
      spacing: 8,
      children: [
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  for (final entry in video.entries) {
                    _selected[entry.snapshotId] = _preferred(entry);
                  }
                }),
          child: Text(en ? 'Select all' : '全選'),
        ),
        TextButton(
          onPressed: _busy ? null : () => setState(_selected.clear),
          child: Text(en ? 'Clear selection' : '取消全選'),
        ),
      ],
    ),
    for (final entry in video.entries)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                key: ValueKey('page-${entry.page}'),
                contentPadding: EdgeInsets.zero,
                value: _selected.containsKey(entry.snapshotId),
                onChanged: _busy
                    ? null
                    : (selected) => setState(() {
                        if (selected == true) {
                          _selected[entry.snapshotId] = _preferred(entry);
                        } else {
                          _selected.remove(entry.snapshotId);
                        }
                      }),
                title: Text(en ? 'Page ${entry.page}' : '第 ${entry.page} 頁'),
                secondary: SizedBox(
                  width: 64,
                  height: 48,
                  child: entry.thumbnailUrl == null
                      ? const Icon(Icons.movie_outlined)
                      : Image.network(
                          entry.thumbnailUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.movie_outlined),
                        ),
                ),
              ),
              if (_selected.containsKey(entry.snapshotId))
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'quality-${entry.snapshotId}-${_selected[entry.snapshotId]?.id}',
                  ),
                  initialValue: _selected[entry.snapshotId]!.id,
                  isExpanded: true,
                  itemHeight: null,
                  items: [
                    for (final format in entry.formats)
                      DropdownMenuItem(
                        value: format.id,
                        child: Text(format.label(en)),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (id) => setState(() {
                          _selected[entry.snapshotId] = entry.formats
                              .firstWhere((format) => format.id == id);
                        }),
                ),
            ],
          ),
        ),
      ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: Text(en ? 'Save separate videos' : '分別下載'),
          selected: !_combine,
          onSelected: _busy ? null : (_) => setState(() => _combine = false),
        ),
        ChoiceChip(
          label: Text(en ? 'Combine into one video' : '合成一支影片'),
          selected: _combine,
          onSelected: _busy ? null : (_) => setState(() => _combine = true),
        ),
      ],
    ),
    Text(
      en
          ? 'Selected pages are saved in post order. Combining re-encodes to a shared size (up to 1080p / 30 fps), adds borders when needed, and retains available audio. Missing audio cannot be restored.'
          : '依貼文順序處理勾選頁數。合成會重新編碼為統一尺寸（最高 1080p／30 fps），必要時加黑邊並保留可取得的音軌；無法還原未取得的聲音。',
    ),
  ];

  Widget _thumbnailUnavailable(bool en) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.image_not_supported_outlined, color: Colors.white70),
        const SizedBox(height: 8),
        Text(
          en ? 'Preview unavailable' : '暫無預覽圖',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    ),
  );
}
