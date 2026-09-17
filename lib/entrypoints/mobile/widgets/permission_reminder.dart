import 'package:flutter/material.dart';
import '../../../infrastructure/engagement/emotion_backmail_service.dart';

/// One prompt per app session; returning from Settings refreshes its status.
final class PermissionReminder extends StatefulWidget {
  const PermissionReminder({required this.child, super.key});
  final Widget child;
  @override
  State<PermissionReminder> createState() => _PermissionReminderState();
}

final class _PermissionReminderState extends State<PermissionReminder>
    with WidgetsBindingObserver {
  bool _shown = false;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    EmotionBackmailService.notificationSettings.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    EmotionBackmailService.notificationSettings.removeListener(_check);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      await EmotionBackmailService.loadNotificationSettings();
      _check();
    } catch (error) {
      debugPrint('Permission refresh failed: $error');
    }
  }

  void _check() {
    if (_shown ||
        _scheduled ||
        !EmotionBackmailService.notificationSettings.value.needsPermission) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted ||
          _shown ||
          !EmotionBackmailService.notificationSettings.value.needsPermission) {
        return;
      }
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && state != AppLifecycleState.resumed) return;
      _shown = true;
      showDialog<void>(
        context: context,
        builder: (_) => const PermissionReminderDialog(),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final class PermissionReminderDialog extends StatefulWidget {
  const PermissionReminderDialog({super.key});
  @override
  State<PermissionReminderDialog> createState() =>
      _PermissionReminderDialogState();
}

final class _PermissionReminderDialogState
    extends State<PermissionReminderDialog> {
  bool _opening = false;
  bool _failed = false;

  Future<void> _open(Future<void> Function() action) async {
    setState(() {
      _opening = true;
      _failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<NotificationSettings>(
    valueListenable: EmotionBackmailService.notificationSettings,
    builder: (context, settings, _) {
      final en = EmotionBackmailService.language.value == AppLanguage.english;
      final notificationMissing =
          !settings.notificationsAllowed || !settings.channelAllowed;
      return AlertDialog(
        scrollable: true,
        title: Text(en ? 'Reminder permissions' : '提醒權限尚未完整開啟'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!settings.needsPermission)
              Text(en ? 'No permissions need attention.' : '目前沒有需要處理的提醒權限。'),
            if (settings.enabled && notificationMissing) ...[
              Text(
                en
                    ? 'Notifications are blocked. Daily reminders cannot be shown.'
                    : '通知權限或通知類別已關閉，無法顯示每日提醒。',
              ),
              TextButton(
                onPressed: _opening
                    ? null
                    : () => _open(
                        EmotionBackmailService.openNotificationSettings,
                      ),
                child: Text(en ? 'Open notification settings' : '前往通知設定'),
              ),
            ],
            if (settings.enabled && !settings.exactAlarmAllowed) ...[
              Text(
                en
                    ? 'Allow alarms & reminders to deliver at the selected time. Otherwise delivery may be delayed.'
                    : '請允許「鬧鐘與提醒」，才能在指定時間準時提醒；未開啟時可能延後。',
              ),
              TextButton(
                onPressed: _opening
                    ? null
                    : () => _open(
                        EmotionBackmailService.requestExactAlarmPermission,
                      ),
                child: Text(en ? 'Open alarms & reminders' : '前往鬧鐘與提醒設定'),
              ),
            ],
            if (_failed)
              Text(
                en
                    ? 'Could not open Settings. Please open this app’s settings manually.'
                    : '無法開啟設定，請手動前往系統的 Terpsichore 設定。',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              settings.needsPermission
                  ? (en ? 'Later' : '稍後再說')
                  : (en ? 'Done' : '完成'),
            ),
          ),
        ],
      );
    },
  );
}
