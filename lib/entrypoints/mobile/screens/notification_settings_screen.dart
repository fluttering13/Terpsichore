import 'package:flutter/material.dart';
import 'package:terpsichore/infrastructure/engagement/emotion_backmail_service.dart';

final class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

final class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late bool _enabled;
  late TimeOfDay _time;
  late AppLanguage _language;
  bool _saving = false;

  bool get _english => _language == AppLanguage.english;

  @override
  void initState() {
    super.initState();
    final settings = EmotionBackmailService.notificationSettings.value;
    _enabled = settings.enabled;
    _time = TimeOfDay(hour: settings.hour, minute: settings.minute);
    _language = EmotionBackmailService.language.value;
  }

  Future<void> _pickTime() async {
    final result = await showTimePicker(context: context, initialTime: _time);
    if (result != null) setState(() => _time = result);
  }

  Future<void> _save({AppLanguage? language}) async {
    if (_saving) return;
    if (language != null) {
      setState(() => _language = language);
    }
    setState(() => _saving = true);
    try {
      await EmotionBackmailService.saveNotificationSettings(
        enabled: _enabled,
        hour: _time.hour,
        minute: _time.minute,
        appLanguage: _language,
      );
      if (!mounted) return;
      final exact =
          EmotionBackmailService.notificationSettings.value.exactAlarmAllowed;
      if (_enabled && !exact) {
        await EmotionBackmailService.requestExactAlarmPermission();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_english ? 'Settings saved' : '設定已儲存')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_english ? 'Settings' : '設定')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _english ? 'Language' : '語言',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<AppLanguage>(
          segments: const [
            ButtonSegment(
              value: AppLanguage.traditionalChinese,
              label: Text('繁體中文'),
            ),
            ButtonSegment(value: AppLanguage.english, label: Text('English')),
          ],
          selected: {_language},
          onSelectionChanged: (selection) => _save(language: selection.first),
        ),
        const SizedBox(height: 24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_english ? 'Daily notifications' : '每日通知'),
          subtitle: Text(
            _enabled
                ? (_english
                      ? 'Remind me when I have not opened the app'
                      : '未開啟 App 時提醒我回來練習')
                : (_english ? 'Notifications are off' : '通知已關閉'),
          ),
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          enabled: _enabled,
          leading: const Icon(Icons.schedule),
          title: Text(_english ? 'Notification time' : '通知時間'),
          subtitle: Text(
            MaterialLocalizations.of(
              context,
            ).formatTimeOfDay(_time, alwaysUse24HourFormat: true),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _enabled ? _pickTime : null,
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_english ? 'Save settings' : '儲存設定'),
        ),
        const SizedBox(height: 10),
        Text(
          _english
              ? 'The default time is 18:00. Turning notifications off also cancels scheduled reminders.'
              : '預設時間為下午 6:00。關閉通知時，也會取消已排程的提醒。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
