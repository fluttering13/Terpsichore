import 'package:terpsichore/infrastructure/engagement/easter_egg_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:terpsichore/infrastructure/engagement/emotion_backmail_service.dart';

import 'screens/ab_analysis_screen.dart';
import 'screens/home_screen.dart';
import 'screens/learning_mode_screen.dart';
import 'screens/music_practice_screen.dart';
import 'screens/video_conversion_screen.dart';
import 'widgets/permission_reminder.dart';

final _eggRoutes = EasterEggRouteObserver();

final class TerpsichoreApp extends StatelessWidget {
  const TerpsichoreApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: EmotionBackmailService.language,
    builder: (context, language, _) => MaterialApp(
      title: 'Terpsichore',
      scaffoldMessengerKey: EasterEggService.instance.messengerKey,
      navigatorObservers: [_eggRoutes],
      locale: Locale(language == AppLanguage.english ? 'en' : 'zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff8d4cf6),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff0f0d14),
        cardTheme: const CardThemeData(
          color: Color(0xff1b1822),
          margin: EdgeInsets.zero,
        ),
        useMaterial3: true,
      ),
      home: const PermissionReminder(child: _HomeShell()),
    ),
  );
}

final class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

final class _HomeShellState extends State<_HomeShell>
    with WidgetsBindingObserver {
  Timer? _eggTimer;
  bool _backgrounded = false;
  bool _eggsReady = false;

  @override
  void initState() {
    super.initState();
    EasterEggService.instance.page = 0;
    WidgetsBinding.instance.addObserver(this);
    _initializeEggs();
  }

  Future<void> _initializeEggs() async {
    await EasterEggService.instance.initialize();
    if (!mounted) return;
    _eggsReady = true;
    if (!_backgrounded) EasterEggService.instance.open();
    _eggTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (EasterEggService.instance.foreground) {
        EasterEggService.instance.engine.tick();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final eggs = EasterEggService.instance;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgrounded = true;
      eggs.foreground = false;
      eggs.engine.suspend();
    } else if (state == AppLifecycleState.inactive) {
      eggs.foreground = false;
      eggs.engine.home(false);
      eggs.engine.clearPause();
    } else if (state == AppLifecycleState.resumed) {
      eggs.foreground = true;
      if (_backgrounded && _eggsReady) {
        eggs.open();
      } else {
        eggs.engine.home(eggs.page == 0 && !eggs.covered);
      }
      _backgrounded = false;
    }
  }

  @override
  void dispose() {
    _eggTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    EasterEggService.instance.engine.suspend();
    super.dispose();
  }

  int _index = 0;
  bool _navigationExpanded = false;

  void _openFeature(int index) => setState(() {
    EasterEggService.instance.selectPage(index);
    _index = index;
    _navigationExpanded = false;
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: EmotionBackmailService.language,
    builder: (context, language, _) {
      final english = language == AppLanguage.english;
      return Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            HomeScreen(onOpenFeature: _openFeature),
            const LearningModeScreen(),
            const AbAnalysisScreen(),
            const MusicPracticeScreen(),
            const VideoConversionScreen(),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.bottomCenter,
            child: _navigationExpanded
                ? NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: _openFeature,
                    destinations: [
                      NavigationDestination(
                        icon: const Icon(Icons.home_outlined),
                        selectedIcon: const Icon(Icons.home),
                        label: english ? 'Home' : '首頁',
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.school_outlined),
                        selectedIcon: const Icon(Icons.school),
                        label: english ? 'Learn' : '學習',
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.compare_outlined),
                        selectedIcon: const Icon(Icons.compare),
                        label: english ? 'A+B Analysis' : 'A+B 分析',
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.music_note_outlined),
                        selectedIcon: const Icon(Icons.music_note),
                        label: english ? 'Music Practice' : '純音樂練習',
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.video_settings_outlined),
                        selectedIcon: const Icon(Icons.video_settings),
                        label: english ? 'Converter' : '影片轉檔',
                      ),
                    ],
                  )
                : Material(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: InkWell(
                      onTap: () => setState(() => _navigationExpanded = true),
                      child: SizedBox(
                        height: 28,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(switch (_index) {
                              0 => Icons.home,
                              1 => Icons.school,
                              2 => Icons.compare,
                              3 => Icons.music_note,
                              _ => Icons.video_settings,
                            }, size: 18),
                            const SizedBox(width: 6),
                            const Icon(Icons.keyboard_arrow_up, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      );
    },
  );
}
