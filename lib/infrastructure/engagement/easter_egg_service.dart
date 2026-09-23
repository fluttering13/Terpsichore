import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/engagement/easter_egg_catalog.dart';
import 'emotion_backmail_service.dart';
import '../../core/engagement/easter_egg_engine.dart';
import '../../core/saved_projects/saved_project.dart';
import '../../core/platform_download/platform_video.dart';

final class EasterEggService {
  EasterEggService._();
  static final instance = EasterEggService._();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final engine = EasterEggEngine(emit: _show);
  Future<void>? _writes;
  File? _file;
  bool foreground = true;
  int page = 0;
  bool covered = false;
  final _pending = <String>{};
  final ValueNotifier<Set<String>> collected = ValueNotifier(const <String>{});
  final downloadedPlatforms = <String>{};
  final projectLastOpened = <String, DateTime>{};
  bool get learningVisible => foreground && page == 1 && !covered;

  Future<void> initialize({File? storageFile}) async {
    if (_writes != null) await _writes;
    try {
      _file = storageFile;
      if (_file == null) {
        final directory = await getApplicationSupportDirectory();
        _file = File('${directory.path}/easter_eggs.json');
      }
      if (await _file!.exists()) {
        final data = jsonDecode(await _file!.readAsString()) as Map;
        final daily = Map<String, String>.from(data['daily'] as Map? ?? data);
        engine.daily.addAll(daily);
        final saved = data['collected'] as List? ?? daily.keys.toList();
        collected.value = Set.unmodifiable({
          ...collected.value,
          ...saved.whereType<String>().where(easterEggs.containsKey),
        });
        downloadedPlatforms.addAll(
          (data['downloadedPlatforms'] as List? ?? []).whereType<String>(),
        );
        final opened = data['projectLastOpened'] as Map? ?? {};
        for (final entry in opened.entries) {
          final at = DateTime.tryParse(entry.value.toString());
          if (at != null) projectLastOpened[entry.key.toString()] = at;
        }
      }
    } catch (error) {
      debugPrint('Unable to load easter eggs: $error');
    }
  }

  Future<void> flush() => _writes ?? Future.value();

  void _show(String id) {
    _pending.add(id);
    collected.value = Set.unmodifiable({...collected.value, id});
    _save();
    showPending();
  }

  void _save() {
    final snapshot = jsonEncode({
      'daily': engine.daily,
      'collected': collected.value.toList(),
      'downloadedPlatforms': downloadedPlatforms.toList(),
      'projectLastOpened': projectLastOpened.map(
        (id, at) => MapEntry(id, at.toUtc().toIso8601String()),
      ),
    });
    final file = _file;
    if (file != null) {
      _writes = (_writes ?? Future<void>.value()).then((_) async {
        try {
          await file.parent.create(recursive: true);
          final temp = File('${file.path}.tmp');
          await temp.writeAsString(snapshot, flush: true);
          await temp.rename(file.path);
        } catch (error) {
          debugPrint('Unable to save daily easter eggs: $error');
        }
      });
    }
  }

  void projectLoaded(String mode, SavedProject project) {
    final opened = projectLastOpened[project.id];
    final lastUsed = opened != null && opened.isAfter(project.updatedAt)
        ? opened
        : project.updatedAt;
    engine.projectLoaded(mode, project.updatedAt, lastUsed);
    projectLastOpened[project.id] = engine.clock();
    _save();
  }

  void downloadCompleted(DownloadPlatform platform) {
    downloadedPlatforms.add(platform.name);
    _save();
    if (DownloadPlatform.values.every(
      (value) => downloadedPlatforms.contains(value.name),
    )) {
      engine.trigger('collector');
    }
  }

  /// Native pickers can report their result before the app resumes.
  void showPending() {
    if (!foreground || _pending.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = messengerKey.currentState;
      if (!foreground || messenger == null) return;
      for (final id in _pending.toList()) {
        final catalog =
            EmotionBackmailService.language.value == AppLanguage.english
            ? easterEggsEnglish
            : easterEggs;
        final egg = catalog[id]!;
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 7),
            content: Text(egg.message),
            showCloseIcon: true,
          ),
        );
        _pending.remove(id);
        unawaited(_vibrate());
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _vibrate() async {
    try {
      await HapticFeedback.vibrate();
    } on MissingPluginException {
      // Platforms without haptics still display the message.
    } on PlatformException catch (error) {
      debugPrint('Unable to vibrate for easter egg: $error');
    }
  }

  void open() {
    foreground = true;
    messengerKey.currentState?.clearSnackBars();
    engine.open();
    engine.home(page == 0 && !covered);
    if (learningVisible) engine.enterLearning();
    showPending();
  }

  void selectPage(int next) {
    if (page == next) return;
    engine.stopListening();
    engine.practice('learning', false, playbackStopped: false);
    engine.practice('ab', false, playbackStopped: false);
    engine.practice('music', false, playbackStopped: false);
    engine.clearPause();
    page = next;
    engine.home(next == 0 && !covered, returned: next == 0);
    if (learningVisible) engine.enterLearning();
  }

  void cover(bool value, {bool returned = false}) {
    if (covered == value) return;
    covered = value;
    if (value) engine.stopListening();
    engine.home(foreground && page == 0 && !value, returned: returned);
    engine.clearPause();
  }

  void count(String id, int threshold, {bool rapid = false}) => engine.count(
    id,
    threshold,
    window: rapid ? const Duration(seconds: 10) : null,
  );
  void mirror({bool ab = false}) {
    count('mirror', 6, rapid: true);
    if (ab) count('sides', 11);
  }

  void exportCompleted() => count('exports', 10);
}

final class EasterEggRouteObserver extends NavigatorObserver {
  void _update(Route<dynamic>? route, {bool returned = false}) {
    EasterEggService.instance.cover(
      route != null && !route.isFirst,
      returned: returned,
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute, returned: route is PageRoute);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _update(newRoute);
}
