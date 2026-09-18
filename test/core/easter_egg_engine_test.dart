import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/engagement/easter_egg_catalog.dart';
import 'package:terpsichore/core/engagement/easter_egg_engine.dart';

void main() {
  late DateTime now;
  late List<String> emitted;
  late EasterEggEngine eggs;
  setUp(() {
    now = DateTime(2026, 9, 18, 12);
    emitted = [];
    eggs = EasterEggEngine(clock: () => now, emit: emitted.add)..open();
  });

  test('catalog includes every named idea in egg.md', () {
    final names = RegExp(
      r'彩蛋名稱：([^\r\n]+)',
    ).allMatches(File('egg.md').readAsStringSync()).map((match) => match[1]);
    expect(easterEggs.values.map((egg) => egg.title), unorderedEquals(names));
    expect(easterEggs.length, 28);
  });

  for (final id in [
    'camera',
    'repeat',
    'sides',
    'hades',
    'notifications',
    'void',
    'return',
  ]) {
    test('$id triggers on eleven, once per app session, then resets', () {
      for (var i = 0; i < 10; i++) {
        eggs.count(id, 11);
      }
      expect(emitted, isEmpty);
      eggs.count(id, 11);
      eggs.count(id, 11);
      expect(emitted, [id]);
      eggs.open();
      for (var i = 0; i < 11; i++) {
        eggs.count(id, 11);
      }
      expect(emitted, [id, id]);
      expect(eggs.daily, isEmpty);
    });
  }

  test('successful exports accumulate only inside the current session', () {
    for (var i = 0; i < 9; i++) {
      eggs.count('exports', 10);
    }
    eggs.open();
    eggs.count('exports', 10);
    expect(emitted, isEmpty);
    for (var i = 0; i < 9; i++) {
      eggs.count('exports', 10);
    }
    expect(emitted, ['exports']);
  });

  for (final entry in {
    'logo': 10,
    'mirror': 6,
    'language': 6,
    'sculpt': 11,
  }.entries) {
    test('${entry.key} requires all events within ten seconds', () {
      void tap() => eggs.count(
        entry.key,
        entry.value,
        window: const Duration(seconds: 10),
      );
      for (var i = 0; i < entry.value - 1; i++) {
        tap();
      }
      now = now.add(const Duration(seconds: 11));
      tap();
      expect(emitted, isEmpty);
      for (var i = 0; i < entry.value - 1; i++) {
        tap();
      }
      expect(emitted, [entry.key]);
    });
  }

  test('daily claims survive restart and become available next local day', () {
    eggs.trigger('bones', oncePerDay: true);
    final stored = jsonEncode(eggs.daily);
    eggs = EasterEggEngine(
      clock: () => now,
      emit: emitted.add,
      daily: Map<String, String>.from(jsonDecode(stored) as Map),
    )..open();
    eggs.trigger('bones', oncePerDay: true);
    expect(emitted, ['bones']);
    now = now.add(const Duration(days: 1));
    eggs.trigger('bones', oncePerDay: true);
    expect(emitted, ['bones', 'bones']);
  });

  test('night is local midnight inclusive and six AM exclusive', () {
    now = DateTime(2026, 9, 18);
    eggs.open();
    now = DateTime(2026, 9, 18, 5, 59);
    eggs.open();
    expect(emitted, ['night']);
    now = DateTime(2026, 9, 19, 6);
    eggs.open();
    expect(emitted, ['night']);
    now = DateTime(2026, 9, 20);
    eggs.open();
    expect(emitted, ['night', 'night']);
  });

  test('calendar eggs require their specific entry and occur daily once', () {
    now = DateTime(2028, 2, 29, 12);
    eggs.open();
    eggs.open();
    expect(emitted, ['leap']);
    now = DateTime(2028, 4, 1, 12);
    eggs.open();
    expect(emitted, ['leap']);
    eggs.home(true);
    eggs.home(false);
    eggs.home(true);
    expect(emitted, ['leap', 'april']);
    now = DateTime(2028, 12, 31, 12);
    eggs.open();
    eggs.home(true);
    expect(emitted, ['leap', 'april']);
    eggs.enterLearning();
    eggs.enterLearning();
    expect(emitted, ['leap', 'april', 'lastBeat']);
  });

  test('home dwell resets when a different route covers home', () {
    eggs.home(true);
    now = now.add(const Duration(seconds: 179));
    eggs.tick();
    expect(emitted, isEmpty);
    eggs.home(false);
    now = now.add(const Duration(minutes: 10));
    eggs.tick();
    expect(emitted, isEmpty);
    eggs.home(true);
    now = now.add(const Duration(minutes: 3));
    eggs.tick();
    eggs.tick();
    expect(emitted, ['gaze']);
  });

  test('frozen requires over 300 seconds at exactly the same paused frame', () {
    void frame(String id, {bool playing = false}) =>
        eggs.learningFrame(id, playing: playing, rate: 1);
    frame('video:0');
    now = now.add(const Duration(seconds: 300));
    eggs.tick();
    expect(emitted, isEmpty);
    frame('video:1');
    now = now.add(const Duration(seconds: 300));
    eggs.tick();
    expect(emitted, isEmpty);
    frame('video:1', playing: true);
    now = now.add(const Duration(minutes: 10));
    eggs.tick();
    expect(emitted, isEmpty);
    frame('video:1');
    now = now.add(const Duration(seconds: 301));
    eggs.tick();
    expect(emitted, ['frozen']);
  });

  test('background time cannot satisfy either dwell condition', () {
    eggs.home(true);
    eggs.learningFrame('frame', playing: false, rate: 1);
    now = now.add(const Duration(seconds: 100));
    eggs.suspend();
    now = now.add(const Duration(hours: 1));
    eggs.tick();
    expect(emitted, isEmpty);
  });

  test('one hundred full loops of one segment wait for playback to stop', () {
    eggs.practice('learning', true);
    for (var i = 0; i < 99; i++) {
      eggs.completedLoop('learning', 'a:0:10');
    }
    eggs.practice('learning', false);
    expect(emitted, isEmpty);
    eggs.practice('learning', true);
    eggs.completedLoop('learning', 'a:0:10');
    expect(emitted, isEmpty);
    eggs.practice('learning', false);
    expect(emitted, ['hundredLoops']);
  });

  test('loop ranges, videos and modes do not pool their repetitions', () {
    for (var i = 0; i < 99; i++) {
      eggs.completedLoop('learning', 'a:0:10');
    }
    eggs.completedLoop('learning', 'a:1:10');
    eggs.completedLoop('music', 'a:0:10');
    eggs.practice('learning', false);
    eggs.practice('music', false);
    expect(emitted, isEmpty);
    for (var i = 0; i < 99; i++) {
      eggs.completedLoop('learning', 'b:1:10');
    }
    eggs.practice('learning', false);
    expect(emitted, isEmpty);
    eggs.open();
    eggs.completedLoop('learning', 'b:1:10');
    eggs.practice('learning', false);
    expect(emitted, isEmpty);
  });

  test('leaving a page cannot pretend that its video has stopped', () {
    eggs.practice('learning', true);
    for (var i = 0; i < 100; i++) {
      eggs.completedLoop('learning', 'a:0:10');
    }
    eggs.practice('learning', false, playbackStopped: false);
    expect(emitted, isEmpty);
    eggs.practice('learning', false);
    expect(emitted, ['hundredLoops']);
  });

  test('rest within a loop is still a continuous New Year practice', () {
    now = DateTime(2026, 12, 31, 23, 59);
    eggs.practice('learning', true);
    now = DateTime(2027, 1, 1, 0, 1);
    eggs.practice('learning', true);
    expect(emitted, isEmpty);
    eggs.practice('learning', false);
    expect(emitted, ['newYear']);
  });

  test('stopping before midnight does not qualify as New Year practice', () {
    now = DateTime(2026, 12, 31, 23, 59);
    eggs.practice('music', true);
    eggs.practice('music', false);
    now = DateTime(2027, 1, 1, 0, 1);
    eggs.practice('music', true);
    eggs.practice('music', false);
    expect(emitted, isEmpty);
  });

  test('Monday is daily across modes; Friday evening resets per entry', () {
    now = DateTime(2026, 9, 21, 12);
    eggs.practice('learning', true);
    eggs.practice('ab', true);
    eggs.open();
    eggs.practice('music', true);
    expect(emitted, ['monday']);
    now = DateTime(2026, 9, 25, 17, 59);
    eggs.open();
    eggs.practice('learning', true);
    eggs.practice('learning', false);
    expect(emitted, ['monday']);
    now = DateTime(2026, 9, 25, 18);
    eggs.practice('learning', true);
    eggs.practice('ab', true);
    eggs.open();
    eggs.practice('music', true);
    expect(emitted, ['monday', 'friday', 'friday']);
  });

  test('restoring speed requires actual slow playback and is daily', () {
    eggs.rate(1, 0.25);
    eggs.rate(0.25, 1);
    expect(emitted, ['quarter']);
    eggs.rate(1, 0.5);
    eggs.learningFrame('a', playing: true, rate: 0.5);
    eggs.rate(0.5, 1);
    expect(emitted, ['quarter', 'unseal']);
    eggs.open();
    eggs.learningFrame('a', playing: true, rate: 0.5);
    eggs.rate(0.5, 1);
    expect(emitted, ['quarter', 'unseal']);
    now = now.add(const Duration(days: 1));
    eggs.learningFrame('a', playing: true, rate: 0.5);
    eggs.rate(0.5, 1);
    expect(emitted, ['quarter', 'unseal', 'unseal']);
  });

  test('unchanged playback speed never increments adjustment count', () {
    for (var i = 0; i < 20; i++) {
      eggs.rate(1, 1);
    }
    expect(emitted, isEmpty);
    for (var i = 0; i < 10; i++) {
      eggs.rate(i.isEven ? 1 : 2, i.isEven ? 2 : 1);
    }
    expect(emitted, isEmpty);
    eggs.rate(1, 2);
    expect(emitted, ['speed']);
  });
}
