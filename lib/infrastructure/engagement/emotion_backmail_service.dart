import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges app-open events to Android's native inactivity alarm and launcher
/// icon controller. Other platforms intentionally behave as a no-op.
final class EmotionBackmailService {
  EmotionBackmailService._();

  static const _channel = MethodChannel('terpsichore/emotion_backmail');
  static final ValueNotifier<int?> onlineStreak = ValueNotifier<int?>(null);
  static final ValueNotifier<String?> notificationMessage =
      ValueNotifier<String?>(null);
  static final ValueNotifier<NotificationSettings> notificationSettings =
      ValueNotifier(const NotificationSettings());
  static final ValueNotifier<AppLanguage> language = ValueNotifier(
    AppLanguage.traditionalChinese,
  );

  static Future<void> recordAppOpen() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      final status = await _channel.invokeMapMethod<String, Object?>(
        'recordOpen',
      );
      onlineStreak.value = (status?['onlineStreak'] as num?)?.toInt();
      notificationMessage.value = status?['message'] as String?;
      await loadNotificationSettings();
    } on MissingPluginException {
      // Keeps widget tests and unsupported build targets independent of Android.
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Emotion backmail initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> loadNotificationSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final data = await _channel.invokeMapMethod<String, Object?>(
        'getNotificationSettings',
      );
      _applySettings(data);
    } on MissingPluginException {
      // Android-only integration.
    }
  }

  static Future<void> saveNotificationSettings({
    required bool enabled,
    required int hour,
    required int minute,
    required AppLanguage appLanguage,
  }) async {
    language.value = appLanguage;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      notificationSettings.value = NotificationSettings(
        enabled: enabled,
        hour: hour,
        minute: minute,
      );
      return;
    }
    try {
      final data = await _channel.invokeMapMethod<String, Object?>(
        'updateNotificationSettings',
        <String, Object>{
          'enabled': enabled,
          'hour': hour,
          'minute': minute,
          'language': appLanguage.code,
        },
      );
      _applySettings(data);
    } on MissingPluginException {
      notificationSettings.value = NotificationSettings(
        enabled: enabled,
        hour: hour,
        minute: minute,
      );
    }
  }

  static Future<void> requestExactAlarmPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('requestExactAlarmPermission');
    } on MissingPluginException {
      // Widget tests and unsupported Android embeddings have no native bridge.
    }
  }

  static Future<bool> testNotification() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>('testNotification') ?? false;
  }

  static Future<void> openNotificationSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('openNotificationSettings');
  }

  static void _applySettings(Map<String, Object?>? data) {
    if (data == null) return;
    notificationSettings.value = NotificationSettings(
      enabled: data['enabled'] as bool? ?? true,
      hour: (data['hour'] as num?)?.toInt() ?? 18,
      minute: (data['minute'] as num?)?.toInt() ?? 0,
      exactAlarmAllowed: data['exactAlarmAllowed'] as bool? ?? true,
      notificationsAllowed: data['notificationsAllowed'] as bool? ?? true,
      channelAllowed: data['channelAllowed'] as bool? ?? true,
    );
    language.value = AppLanguage.fromCode(data['language'] as String?);
    final message = data['message'] as String?;
    if (message != null && message.isNotEmpty) {
      notificationMessage.value = message;
    }
  }
}

enum AppLanguage {
  traditionalChinese('zh-TW'),
  english('en');

  const AppLanguage(this.code);
  final String code;

  static AppLanguage fromCode(String? code) =>
      code == english.code ? english : traditionalChinese;
}

final class NotificationSettings {
  const NotificationSettings({
    this.enabled = true,
    this.hour = 18,
    this.minute = 0,
    this.exactAlarmAllowed = true,
    this.notificationsAllowed = true,
    this.channelAllowed = true,
  });

  final bool enabled;
  final int hour;
  final int minute;
  final bool exactAlarmAllowed;
  final bool notificationsAllowed;
  final bool channelAllowed;
  bool get needsPermission =>
      enabled &&
      (!notificationsAllowed || !channelAllowed || !exactAlarmAllowed);
}
