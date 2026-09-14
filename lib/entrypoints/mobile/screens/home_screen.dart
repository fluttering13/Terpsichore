import 'package:flutter/material.dart';

final class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.onOpenFeature, super.key});

  final ValueChanged<int> onOpenFeature;

  @override
  Widget build(BuildContext context) => SafeArea(
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
                child: Image.asset('asset/logo.png', fit: BoxFit.contain),
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('選擇練習方式', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 5),
      Text(
        '今天想從哪裡開始？',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
      ),
      const SizedBox(height: 14),
      _FeatureCard(
        icon: Icons.school_outlined,
        accent: const Color(0xffc69cff),
        title: '學習模式',
        description: '影片、自拍鏡頭、八拍校正、片段循環與錄影',
        actionLabel: '開始舞蹈練習',
        onTap: () => onOpenFeature(1),
      ),
      const SizedBox(height: 10),
      _FeatureCard(
        icon: Icons.compare_outlined,
        accent: const Color(0xff77c8ff),
        title: 'A+B 分析',
        description: '並排比較兩支影片，校準速度、時間軸與輸出',
        actionLabel: '比較兩支影片',
        onTap: () => onOpenFeature(2),
      ),
      const SizedBox(height: 10),
      _FeatureCard(
        icon: Icons.graphic_eq,
        accent: const Color(0xffffc879),
        title: '純音樂練習',
        description: '原聲或 AI 六軌分離，自選聲部循環練習',
        actionLabel: '選擇練習音樂',
        onTap: () => onOpenFeature(3),
      ),
    ],
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
