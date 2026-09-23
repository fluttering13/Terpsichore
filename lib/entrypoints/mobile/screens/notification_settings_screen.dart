import 'package:terpsichore/infrastructure/engagement/easter_egg_service.dart';
import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import 'package:terpsichore/core/engagement/easter_egg_catalog.dart';
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
    if (language != null && language != _language) {
      EasterEggService.instance.count('language', 6, rapid: true);
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
    body: CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
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
                  ButtonSegment(
                    value: AppLanguage.english,
                    label: Text('English'),
                  ),
                ],
                selected: {_language},
                onSelectionChanged: (selection) =>
                    _save(language: selection.first),
              ),
              const SizedBox(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_english ? 'Daily notifications' : '每日通知'),
                subtitle: Text(
                  _enabled
                      ? (_english
                            ? 'Notify me every day, even if I opened the app'
                            : '每天固定時間通知，當天開過 App 也會收到')
                      : (_english ? 'Notifications are off' : '通知已關閉'),
                ),
                value: _enabled,
                onChanged: (value) {
                  EasterEggService.instance.count('notifications', 11);
                  setState(() => _enabled = value);
                },
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
              OutlinedButton.icon(
                onPressed: () async {
                  EasterEggService.instance.count('oracleSoundcheck', 3);
                  try {
                    final easterEgg =
                        await EmotionBackmailService.testNotification();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          easterEgg
                              ? (_english
                                    ? 'Test notifications started.'
                                    : '測試通知已啟動。')
                              : _english
                              ? 'Test scheduled in about 10 seconds; check notification permissions if nothing arrives.'
                              : '約 10 秒後發送測試通知；若沒收到，請確認系統通知權限。',
                        ),
                      ),
                    );
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            appText(context, '測試排程失敗：{0}', [
                              appError(context, error),
                            ]),
                          ),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(_english ? 'Test notification' : '發送測試通知'),
              ),
              Text(
                _english
                    ? 'The default time is 18:00. Turning notifications off also cancels scheduled reminders.'
                    : '預設時間為下午 6:00。關閉通知時，也會取消已排程的提醒。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              ValueListenableBuilder<Set<String>>(
                valueListenable: EasterEggService.instance.collected,
                builder: (context, collected, _) {
                  final catalog = _english ? easterEggsEnglish : easterEggs;
                  final entries = catalog.entries
                      .where((entry) => collected.contains(entry.key))
                      .toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_english ? 'Collected easter eggs: ' : '已收集的彩蛋：'}${entries.length} / ${catalog.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (entries.isEmpty)
                        Text(
                          _english
                              ? 'No easter eggs collected yet. Explore and practice to discover them!'
                              : '尚未收集到彩蛋，繼續探索與練習來發現吧！',
                        ),
                      for (final entry in entries)
                        Card(
                          child: ExpansionTile(
                            key: PageStorageKey('collected-egg-${entry.key}'),
                            leading: const Icon(Icons.auto_awesome_outlined),
                            title: Text(entry.value.title),
                            expandedCrossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            children: [
                              Text(
                                _english ? 'Displayed line' : '呈現台詞',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(entry.value.message),
                              const SizedBox(height: 12),
                              Text(
                                _english ? 'How to trigger' : '觸發方式',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(entry.value.trigger),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: GestureDetector(
            key: const ValueKey('notification-empty-space'),
            behavior: HitTestBehavior.opaque,
            onTap: () => EasterEggService.instance.count('void', 11),
            child: const SizedBox(height: 96),
          ),
        ),
      ],
    ),
  );
}
