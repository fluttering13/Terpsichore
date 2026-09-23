import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/engagement/easter_egg_engine.dart';

void main() {
  late DateTime now;
  late List<String> emitted;
  late EasterEggEngine eggs;
  setUp(() {
    now = DateTime(2026, 9, 23, 12);
    emitted = [];
    eggs = EasterEggEngine(emit: emitted.add, clock: () => now);
  });

  void music(
    Set<String> stems, {
    bool playing = true,
    bool original = false,
    bool separated = true,
  }) => eggs.musicPlayback(
    playing: playing,
    separated: separated,
    original: original,
    stems: stems,
  );

  for (final solo in ['drums', 'bass']) {
    test('$solo requires thirty seconds of actual continuous playback', () {
      music({solo});
      now = now.add(const Duration(seconds: 29));
      eggs.tick();
      expect(emitted, isEmpty);
      now = now.add(const Duration(seconds: 1));
      eggs.tick();
      expect(
        emitted,
        unorderedEquals([
          'vocalVacation',
          solo == 'drums' ? 'heartbeat' : 'bassLover',
        ]),
      );
      eggs.tick();
      expect(emitted.length, 2);
    });
  }

  test(
    'selection alone, original audio and missing separation do not count',
    () {
      for (final action in [
        () => music({'drums'}, playing: false),
        () => music({'drums'}, original: true),
        () => music({'drums'}, separated: false),
        () => music({}),
        () => music({'vocals', 'drums'}),
      ]) {
        action();
        now = now.add(const Duration(minutes: 1));
        eggs.tick();
      }
      expect(emitted, isEmpty);
    },
  );

  test('pause or buffering resets the continuous listening interval', () {
    music({'drums'});
    now = now.add(const Duration(seconds: 20));
    music({'drums'}, playing: false);
    now = now.add(const Duration(minutes: 1));
    eggs.tick();
    music({'drums'});
    now = now.add(const Duration(seconds: 20));
    eggs.tick();
    expect(emitted, isEmpty);
    now = now.add(const Duration(seconds: 10));
    eggs.tick();
    expect(emitted, contains('heartbeat'));
  });

  test('changing to vocals or source cancels instrumental timers', () {
    music({'bass'});
    now = now.add(const Duration(seconds: 29));
    music({'vocals'});
    now = now.add(const Duration(seconds: 2));
    eggs.tick();
    expect(emitted, isEmpty);
    music({'drums'});
    now = now.add(const Duration(seconds: 29));
    eggs.segment('music', 'different-file');
    now = now.add(const Duration(seconds: 2));
    eggs.tick();
    expect(emitted, isEmpty);
  });

  test('all six separated stems must actually play together', () {
    final all = {'drums', 'bass', 'vocals', 'guitar', 'piano', 'other'};
    music(all, playing: false);
    music(all, original: true);
    music(all, separated: false);
    music({'drums', 'bass', 'vocals', 'guitar', 'piano'});
    expect(emitted, isEmpty);
    music(all);
    expect(emitted, ['sixGods']);
  });

  test('silent playback requires 30 seconds and interruption resets it', () {
    eggs.listening('ab', {'silence'});
    now = now.add(const Duration(seconds: 29));
    eggs.tick();
    expect(emitted, isEmpty);
    eggs.stopListening();
    now = now.add(const Duration(minutes: 10));
    eggs.tick();
    expect(emitted, isEmpty);
    eggs.listening('ab', {'silence'});
    now = now.add(const Duration(seconds: 30));
    eggs.tick();
    expect(emitted, ['silence']);
  });

  test('five fully rested loops belong to the same mode and segment', () {
    for (var i = 0; i < 4; i++) {
      eggs.restedLoop('music', 'one', const Duration(seconds: 10));
    }
    eggs.restedLoop('learning', 'one', const Duration(seconds: 10));
    expect(emitted, isEmpty);
    eggs.restedLoop('music', 'two', const Duration(seconds: 10));
    for (var i = 0; i < 3; i++) {
      eggs.restedLoop('music', 'two', const Duration(seconds: 10));
    }
    expect(emitted, isEmpty);
    eggs.restedLoop('music', 'two', const Duration(seconds: 10));
    expect(emitted, ['intermission']);
  });

  test('short rests and background sessions cannot earn intermission', () {
    for (var i = 0; i < 5; i++) {
      eggs.restedLoop('learning', 'one', const Duration(seconds: 9));
    }
    for (var i = 0; i < 4; i++) {
      eggs.restedLoop('learning', 'one', const Duration(seconds: 10));
    }
    final epoch = eggs.activityEpoch;
    eggs.suspend();
    expect(eggs.activityEpoch, greaterThan(epoch));
    eggs.restedLoop('learning', 'one', const Duration(seconds: 10));
    expect(emitted, isEmpty);
  });

  test('yesterday uses local calendar dates and waits for playback', () {
    now = DateTime(2026, 10, 1, 0, 1);
    final saved = DateTime(2026, 9, 30, 23, 59);
    eggs.projectLoaded('ab', saved, saved);
    expect(emitted, isEmpty);
    eggs.projectPlayback('music');
    expect(emitted, isEmpty);
    eggs.projectPlayback('ab');
    eggs.projectPlayback('ab');
    expect(emitted, ['yesterday']);
  });

  test(
    'reunion requires 30 days since use and successful project playback',
    () {
      final old = now.subtract(const Duration(days: 40));
      eggs.projectLoaded(
        'learning',
        old,
        now.subtract(const Duration(days: 29)),
      );
      eggs.projectPlayback('learning');
      expect(emitted, isEmpty);
      eggs.projectLoaded(
        'learning',
        old,
        now.subtract(const Duration(days: 30)),
      );
      expect(emitted, isEmpty);
      eggs.projectPlayback('learning');
      expect(emitted, ['reunion']);
    },
  );

  test('replacing a loaded project with new media cancels pending eggs', () {
    final old = now.subtract(const Duration(days: 31));
    eggs.projectLoaded('music', old, old);
    eggs.clearProject('music');
    eggs.projectPlayback('music');
    expect(emitted, isEmpty);
  });
}
