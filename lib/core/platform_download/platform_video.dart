enum DownloadPlatform {
  youtube('YouTube'),
  instagram('Instagram'),
  facebook('Facebook'),
  threads('Threads');

  const DownloadPlatform(this.label);
  final String label;
}

final class PlatformVideoLink {
  const PlatformVideoLink(this.uri, this.platform);
  final Uri uri;
  final DownloadPlatform platform;
  bool get isInstagramStory =>
      platform == DownloadPlatform.instagram &&
      uri.path.startsWith('/stories/');

  static PlatformVideoLink parse(String input) {
    final matches = RegExp(
      r'https?://[^\s<>"\u3000]+',
      caseSensitive: false,
    ).allMatches(input.trim()).toList();
    if (matches.length != 1) throw const DownloadException('INVALID_URL');
    final text = matches.single
        .group(0)!
        .replaceFirst(RegExp(r'[)\]。，、！!]+$'), '');
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 80 && uri.port != 443)) {
      throw const DownloadException('INVALID_URL');
    }
    final host = uri.host.toLowerCase();
    bool belongs(String domain) => host == domain || host.endsWith('.$domain');
    final platform = switch (host) {
      _ when belongs('youtube.com') || belongs('youtu.be') =>
        DownloadPlatform.youtube,
      _ when belongs('instagram.com') => DownloadPlatform.instagram,
      _ when belongs('facebook.com') || belongs('fb.watch') =>
        DownloadPlatform.facebook,
      _ when belongs('threads.net') || belongs('threads.com') =>
        DownloadPlatform.threads,
      _ => throw const DownloadException('INVALID_URL'),
    };
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    final videoLink = switch (platform) {
      DownloadPlatform.youtube =>
        belongs('youtu.be')
            ? RegExp(r'^/[^/]+$').hasMatch(path)
            : (path == '/watch' &&
                      (uri.queryParameters['v']?.isNotEmpty ?? false)) ||
                  RegExp(r'^/(shorts|live|embed|v)/[^/]+$').hasMatch(path),
      DownloadPlatform.instagram =>
        RegExp(r'^/(?:[^/]+/)?(?:p|reel|reels|tv)/[^/]+$').hasMatch(path) ||
            RegExp(
              r'^/stories/(?!highlights/)[A-Za-z0-9_.]+/[0-9]+$',
            ).hasMatch(path) ||
            RegExp(r'^/share/[^/]+(?:/[^/]+)?$').hasMatch(path),
      DownloadPlatform.facebook =>
        belongs('fb.watch')
            ? RegExp(r'^/[^/]+$').hasMatch(path)
            : RegExp(
                    r'^/(?:share/|reel/|.*(?:videos|posts|permalink)/).+',
                  ).hasMatch(path) ||
                  (['/watch', '/video.php', '/story.php'].contains(path) &&
                      ['v', 'story_fbid'].any(
                        (key) => uri.queryParameters[key]?.isNotEmpty ?? false,
                      )),
      DownloadPlatform.threads => RegExp(
        r'^/(?:@[^/]+/post|t|share)/[^/]+$',
      ).hasMatch(path),
    };
    if (!videoLink) {
      throw const DownloadException('VIDEO_LINK_REQUIRED');
    }
    return PlatformVideoLink(
      uri.replace(scheme: 'https', fragment: ''),
      platform,
    );
  }
}

final class PlatformVideoFormat {
  const PlatformVideoFormat({
    required this.id,
    required this.width,
    required this.height,
    required this.extension,
    this.fps = 0,
    this.bitrate = 0,
    this.bytes = 0,
    this.mergeAudio = false,
    this.silent = false,
  });

  factory PlatformVideoFormat.fromMap(Map<Object?, Object?> map) =>
      PlatformVideoFormat(
        id: map['id'] as String,
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
        extension: map['extension'] as String,
        fps: (map['fps'] as num?)?.toDouble() ?? 0,
        bitrate: (map['bitrate'] as num?)?.toDouble() ?? 0,
        bytes: (map['bytes'] as num?)?.toInt() ?? 0,
        mergeAudio: map['mergeAudio'] == true,
        silent: map['silent'] == true,
      );

  final String id;
  final int width, height, bytes;
  final double fps, bitrate;
  final String extension;
  final bool mergeAudio, silent;

  String label(bool english) {
    final resolution = width > 0 && height > 0
        ? '$width × $height'
        : height > 0
        ? '${height}p'
        : (english ? 'Original · resolution unknown' : '原始畫質・解析度未知');
    return [
      resolution,
      if (fps > 0)
        '${fps.toStringAsFixed(fps == fps.roundToDouble() ? 0 : 1)} fps',
      if (bitrate > 0) '${bitrate.round()} kbps',
      mergeAudio ? 'MP4 / MKV' : extension.toUpperCase(),
      if (silent) (english ? 'Audio not found' : '尚未取得音軌'),
      if (bytes > 0)
        '${english ? 'about' : '約'} ${(bytes / 1048576).toStringAsFixed(1)} MB${mergeAudio ? (english ? ' + audio' : '＋音軌') : ''}',
    ].join(' · ');
  }
}

final class PlatformVideo {
  const PlatformVideo({
    required this.snapshotId,
    required this.title,
    required this.formats,
    this.thumbnailUrl,
    this.firstVideoOnly = false,
    this.page = 1,
    this.entries = const [],
  });
  factory PlatformVideo.fromMap(Map<Object?, Object?> map) => PlatformVideo(
    snapshotId: map['snapshotId'] as String,
    title: map['title'] as String,
    thumbnailUrl: map['thumbnailUrl'] as String?,
    firstVideoOnly: map['firstVideoOnly'] == true,
    page: (map['page'] as num?)?.toInt() ?? 1,
    entries: (map['entries'] as List? ?? const [])
        .map((entry) => PlatformVideo.fromMap(entry as Map))
        .toList(),
    formats: (map['formats'] as List)
        .map((value) => PlatformVideoFormat.fromMap(value as Map))
        .toList(),
  );
  final String snapshotId, title;
  final String? thumbnailUrl;
  final bool firstVideoOnly;
  final List<PlatformVideoFormat> formats;
  final int page;
  final List<PlatformVideo> entries;
}

final class DownloadProgress {
  const DownloadProgress(
    this.jobId,
    this.phase,
    this.fraction, {
    this.item = 0,
    this.total = 0,
  });
  final String jobId, phase;
  final double? fraction;
  final int item, total;
}

final class DownloadReceipt {
  const DownloadReceipt(this.uri, this.location, {this.issues = const []});
  final String uri, location;
  final List<String> issues;
}

abstract interface class PlatformVideoDownloader {
  Stream<DownloadProgress> get progress;
  Future<PlatformVideo> inspect(String url, String jobId);
  Future<DownloadReceipt> download(
    PlatformVideo video,
    PlatformVideoFormat format,
    String jobId,
  );
  Future<void> cancel(String jobId);
  Future<DownloadReceipt> downloadSelection(
    List<PlatformVideo> videos,
    List<PlatformVideoFormat> formats,
    String jobId, {
    required bool combine,
  });
}

final class DownloadException implements Exception {
  const DownloadException(this.code);
  final String code;

  String message(bool english) => switch (code) {
    'INVALID_URL' =>
      english
          ? 'Paste one YouTube, Instagram, Facebook or Threads video link.'
          : '請貼上一個 YouTube、Instagram、Facebook 或 Threads 影片連結。',
    'VIDEO_LINK_REQUIRED' =>
      english
          ? 'Use an individual video or post link, not a profile or playlist.'
          : '請使用單支影片或貼文連結，不能使用個人首頁或播放清單。',
    'ACCESS_RESTRICTED' =>
      english
          ? 'This video may be private, require login or age verification, or the platform denied access. It cannot be downloaded without public access.'
          : '此影片可能非公開、需要登入或年齡驗證，或平台拒絕存取。請確認影片可公開觀看後再試。',
    'IG_LOGIN_REQUIRED' =>
      english
          ? 'Sign in to Instagram or import your session to read this story.'
          : '此限動需要 Instagram 登入狀態，請登入或匯入登入狀態後再試。',
    'IG_LOGIN_EXPIRED' =>
      english
          ? 'Instagram no longer accepts this session. Sign in again or import a new session.'
          : 'Instagram 登入狀態已失效，請重新登入或匯入新的登入狀態。',
    'IG_ACCESS_DENIED' =>
      english
          ? 'Instagram denied access with this session. Your follow request may not be approved, you may not be on the Close Friends list, or the session may be invalid. Check that this account can view the original story; then sign in again if needed.'
          : '使用目前登入狀態仍無法存取。可能尚未獲准追蹤對方、未在摯友名單，或登入狀態失效。請先確認此帳號能在 IG 觀看原始限動；必要時重新登入。',
    'IG_CHALLENGE_REQUIRED' =>
      english
          ? 'Instagram requires additional verification. Complete it in Instagram, then sign in again or import an updated session.'
          : 'Instagram 要求額外驗證。請先在 IG 完成驗證，再重新登入或匯入更新的登入狀態。',
    'IG_STORY_UNAVAILABLE' =>
      english
          ? 'This story may have expired, been removed, or be hidden from this account. Check the original link in Instagram.'
          : '此限動可能已過期、被刪除，或未對此帳號開放。請在 IG 確認原始連結。',
    'IG_LOGIN_UNAVAILABLE' =>
      english
          ? 'Unable to open Instagram sign-in. Try importing your session instead.'
          : '無法開啟 Instagram 登入頁，請改用匯入登入狀態。',
    'IG_INVALID_COOKIES' =>
      english
          ? 'Choose a Netscape cookies.txt file with a valid Instagram session.'
          : '請選擇包含有效 Instagram 登入狀態的 Netscape cookies.txt 檔案。',
    'PROTECTED' =>
      english
          ? 'This video is protected and cannot be downloaded.'
          : '此影片有內容保護，無法下載。',
    'UNAVAILABLE' =>
      english
          ? 'The video was removed or is unavailable in your region. Check the original link.'
          : '影片已移除或在目前地區無法觀看，請確認原始連結。',
    'RATE_LIMITED' =>
      english
          ? 'The platform is limiting requests. Try again later.'
          : '平台暫時限制存取次數，請稍後再試。',
    'NETWORK' || 'TIMEOUT' =>
      english
          ? 'Connection failed or timed out. Check your network and try again.'
          : '連線失敗或逾時，請確認網路後重試。',
    'STORAGE_PERMISSION' =>
      english
          ? 'Unable to save the video. Check local storage permissions and try again.'
          : '無法儲存影片，請確認本機儲存權限後再試。',
    'STORAGE_FULL' =>
      english
          ? 'Not enough storage. Free up space and try again.'
          : '儲存空間不足，請清出空間後再試。',
    'LIVE_UNSUPPORTED' =>
      english
          ? 'Live and upcoming streams are not supported. Try after the video is published.'
          : '暫不支援直播中或尚未開始的影片，請在影片發布後再試。',
    'NO_VIDEO' =>
      english
          ? 'No downloadable video was found in this post.'
          : '這則貼文沒有可下載的影片。',
    'EXPIRED' =>
      english
          ? 'Video information expired. Analyze the link again.'
          : '影片資訊已過期，請重新解析連結。',
    'CANCELLED' => english ? 'Cancelled.' : '已取消。',
    'UNSUPPORTED_PLATFORM' =>
      english
          ? 'Video downloads are currently available on Android only.'
          : '平台影片下載目前僅支援 Android。',
    'BUSY' =>
      english
          ? 'Another task is running. Wait or cancel it first.'
          : '另一項工作正在進行，請等候完成或先取消。',
    _ =>
      english
          ? 'Unable to read or download this video. It may require access permission, or the platform changed its video format. Check the original link and try again later.'
          : '目前無法解析或下載這支影片，可能需要存取權限，或平台已調整影片格式。請確認原始連結，稍後再試。',
  };
}
