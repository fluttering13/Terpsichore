import 'package:terpsichore/infrastructure/engagement/easter_egg_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:terpsichore/infrastructure/engagement/emotion_backmail_service.dart';
import 'notification_settings_screen.dart';

final class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.onOpenFeature, super.key});

  final ValueChanged<int> onOpenFeature;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: EmotionBackmailService.language,
    builder: (context, _, _) => SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final landscape = constraints.maxWidth > constraints.maxHeight;
          final cover = _BrandCover(compact: landscape);
          final features = _FeatureMenu(onOpenFeature: onOpenFeature);
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xff111b2a), Color(0xff0f0d14)],
              ),
            ),
            child: landscape
                ? Row(
                    children: [
                      Expanded(child: cover),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(8, 16, 18, 16),
                          child: features,
                        ),
                      ),
                    ],
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: Column(
                      children: [cover, const SizedBox(height: 18), features],
                    ),
                  ),
          );
        },
      ),
    ),
  );
}

final class _BrandCover extends StatelessWidget {
  const _BrandCover({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(compact ? 18 : 0),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: compact ? 380 : 410),
          child: AspectRatio(
            aspectRatio: 1,
            child: Card(
              elevation: 12,
              shadowColor: const Color(0xffd6ad68).withValues(alpha: 0.28),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(
                  color: const Color(0xffd6ad68).withValues(alpha: 0.55),
                ),
              ),
              child: ColoredBox(
                color: const Color(0xfffffbf5),
                child: ValueListenableBuilder<int?>(
                  valueListenable: EmotionBackmailService.onlineStreak,
                  builder: (context, days, _) => GestureDetector(
                    onTap: () => EasterEggService.instance.count(
                      'logo',
                      10,
                      rapid: true,
                    ),
                    onLongPress: (days ?? 0) < 100
                        ? null
                        : () async {
                            EasterEggService.instance.engine.trigger('secret');
                            final save = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                content: const Text(
                                  '一百天。連 Moirai 都替你記下來了。這份紀錄，本女神准你帶走。',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('關閉'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('儲存紀念圖'),
                                  ),
                                ],
                              ),
                            );
                            if (save != true) return;
                            try {
                              final data = await rootBundle.load(
                                'asset/logo2.png',
                              );
                              final result = await SaverGallery.saveImage(
                                data.buffer.asUint8List(
                                  data.offsetInBytes,
                                  data.lengthInBytes,
                                ),
                                fileName: 'Terpsichore-100-days.png',
                                skipIfExists: false,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result.isSuccess
                                        ? '百日紀念圖已儲存'
                                        : '儲存失敗，請確認相簿權限',
                                  ),
                                ),
                              );
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('無法儲存百日紀念圖')),
                              );
                            }
                          },
                    child: Image.asset(
                      (days ?? 0) >= 100 ? 'asset/logo2.png' : 'asset/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 12),
          Text(
            'Dance · Learn · Grow',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: const Color(0xffe2c18a),
              letterSpacing: 2.4,
            ),
          ),
        ],
      ],
    ),
  );
}

final class _FeatureMenu extends StatelessWidget {
  const _FeatureMenu({required this.onOpenFeature});

  final ValueChanged<int> onOpenFeature;

  @override
  Widget build(BuildContext context) {
    final english =
        EmotionBackmailService.language.value == AppLanguage.english;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _LoginStreakCard(),
        const SizedBox(height: 14),
        Text(
          english ? 'Choose a practice mode' : '選擇練習方式',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 5),
        Text(
          english ? 'Where would you like to begin today?' : '今天想從哪裡開始？',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 14),
        _FeatureCard(
          icon: Icons.school_outlined,
          accent: const Color(0xffc69cff),
          title: english ? 'Learning mode' : '學習模式',
          description: english
              ? 'Video, selfie camera, eight-count alignment, loops and recording'
              : '影片、自拍鏡頭、八拍校正、片段循環與錄影',
          actionLabel: english ? 'Start dance practice' : '開始舞蹈練習',
          onTap: () => onOpenFeature(1),
        ),
        const SizedBox(height: 10),
        _FeatureCard(
          icon: Icons.compare_outlined,
          accent: const Color(0xff77c8ff),
          title: english ? 'A+B analysis' : 'A+B 分析',
          description: english
              ? 'Compare two videos side by side and align speed and timing'
              : '並排比較兩支影片，校準速度、時間軸與輸出',
          actionLabel: english ? 'Compare videos' : '比較兩支影片',
          onTap: () => onOpenFeature(2),
        ),
        const SizedBox(height: 10),
        _FeatureCard(
          icon: Icons.graphic_eq,
          accent: const Color(0xffffc879),
          title: english ? 'Music practice' : '純音樂練習',
          description: english
              ? 'Original audio or AI six-stem separation with custom loops'
              : '原聲或 AI 六軌分離，自選聲部循環練習',
          actionLabel: english ? 'Choose practice music' : '選擇練習音樂',
          onTap: () => onOpenFeature(3),
        ),
        const SizedBox(height: 10),
        _FeatureCard(
          icon: Icons.video_settings_outlined,
          accent: const Color(0xff65dbc4),
          title: english ? 'Video converter' : '影片轉檔',
          description: english
              ? 'Detect MOV, MP4 and other inputs and choose an output format'
              : '自動偵測 MOV、MP4 等輸入格式，自選輸出格式',
          actionLabel: english ? 'Choose and convert a video' : '選擇影片並轉檔',
          onTap: () => onOpenFeature(4),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(
              english ? 'Notification & language settings' : '通知與語言設定',
            ),
            subtitle: Text(
              english
                  ? 'Time, on/off, Traditional Chinese / English'
                  : '時間、開關、繁體中文 / English',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationSettingsScreen(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _LoginStreakCard extends StatelessWidget {
  const _LoginStreakCard();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: EmotionBackmailService.language,
    builder: (context, language, _) {
      final english = language == AppLanguage.english;
      return ValueListenableBuilder<int?>(
        valueListenable: EmotionBackmailService.onlineStreak,
        builder: (context, days, _) => ValueListenableBuilder<String?>(
          valueListenable: EmotionBackmailService.notificationMessage,
          builder: (context, message, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xff33254c), Color(0xff22243d)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xffd6ad68).withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x22f2c879),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: 46,
                      child: Icon(
                        Icons.local_fire_department_rounded,
                        color: Color(0xfff2c879),
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          days == null
                              ? (english
                                    ? 'Loading login history…'
                                    : '正在讀取登入紀錄…')
                              : (english
                                    ? '$days-day login streak'
                                    : '已連續登入 $days 天'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: const Color(0xffffe3ad),
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message ??
                              (english
                                  ? "Preparing today's message from Terpsichore…"
                                  : '正在準備 Terpsichore 的今日訊息…'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

final class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SizedBox.square(
                dimension: 54,
                child: Icon(icon, color: accent, size: 30),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    actionLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 17, color: accent),
          ],
        ),
      ),
    ),
  );
}
