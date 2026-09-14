import 'package:flutter/material.dart';

import 'screens/ab_analysis_screen.dart';
import 'screens/home_screen.dart';
import 'screens/learning_mode_screen.dart';
import 'screens/music_practice_screen.dart';

final class TerpsichoreApp extends StatelessWidget {
  const TerpsichoreApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Terpsichore',
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
    home: const _HomeShell(),
  );
}

final class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

final class _HomeShellState extends State<_HomeShell> {
  int _index = 0;
  bool _navigationExpanded = false;

  void _openFeature(int index) => setState(() {
    _index = index;
    _navigationExpanded = false;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _index,
      children: [
        HomeScreen(onOpenFeature: _openFeature),
        const LearningModeScreen(),
        const AbAnalysisScreen(),
        const MusicPracticeScreen(),
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
                onDestinationSelected: (value) => setState(() {
                  _index = value;
                  _navigationExpanded = false;
                }),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: '首頁',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.school_outlined),
                    selectedIcon: Icon(Icons.school),
                    label: '學習',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.compare_outlined),
                    selectedIcon: Icon(Icons.compare),
                    label: 'A+B 分析',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.music_note_outlined),
                    selectedIcon: Icon(Icons.music_note),
                    label: '純音樂練習',
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
                          _ => Icons.music_note,
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
}
