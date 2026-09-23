import 'package:flutter/services.dart';
import '../../core/platform_download/platform_video.dart';

abstract interface class InstagramSession {
  Future<bool> hasSession();
  Future<bool> authenticate({required bool importFile, required bool english});
  Future<void> clear();
}

final class NativeInstagramSession implements InstagramSession {
  const NativeInstagramSession();
  static const _channel = MethodChannel('terpsichore/instagram_session');

  Future<T?> _call<T>(String method, [Map<String, Object>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw DownloadException(e.code);
    } on MissingPluginException {
      throw const DownloadException('UNSUPPORTED_PLATFORM');
    }
  }

  @override
  Future<bool> hasSession() async => await _call<bool>('status') ?? false;
  @override
  Future<bool> authenticate({
    required bool importFile,
    required bool english,
  }) async =>
      await _call<bool>('authenticate', {
        'mode': importFile ? 'import' : 'login',
        'english': english,
      }) ??
      false;
  @override
  Future<void> clear() async {
    await _call<void>('clear');
  }
}
