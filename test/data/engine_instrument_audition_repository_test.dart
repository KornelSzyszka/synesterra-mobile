import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/audio/audition_engine.dart';
import 'package:synesterra/data/repositories/impl/engine_instrument_audition_repository.dart';
import 'package:synesterra_core/synesterra_core.dart';

class FakeSource implements AuditionSource {
  FakeSource(this.id, this.wav);
  final String id;
  final Uint8List wav;
}

class FakeVoice implements AuditionVoice {
  FakeVoice(this.source, this.volume);
  final FakeSource source;
  final double volume;
}

class FakeEngine implements AuditionEngine {
  final events = <String>[];
  final voices = <FakeVoice>[];
  int starts = 0;
  bool failStart = false;
  bool failLoad = false;
  bool disposed = false;
  final unloaded = <String>[];

  @override
  Future<void> start() async {
    starts++;
    if (failStart) throw StateError('no audio device');
  }

  @override
  Future<AuditionSource> load(String id, Uint8List wav) async {
    events.add('load $id');
    if (failLoad) throw StateError('load failed');
    return FakeSource(id, wav);
  }

  @override
  AuditionVoice play(AuditionSource source, {double volume = 1}) {
    events.add('play ${(source as FakeSource).id}');
    final voice = FakeVoice(source, volume);
    voices.add(voice);
    return voice;
  }

  @override
  Future<void> stop(AuditionVoice voice) async {
    events.add('stop ${(voice as FakeVoice).source.id}');
  }

  @override
  Future<void> unload(AuditionSource source) async {
    final id = (source as FakeSource).id;
    events.add('unload $id');
    unloaded.add(id);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class CapturingEngine extends FakeEngine {
  CapturingEngine(this.onLoad);

  final void Function(Uint8List) onLoad;

  @override
  Future<AuditionSource> load(String id, Uint8List wav) {
    onLoad(wav);
    return super.load(id, wav);
  }
}

class SecondPlayFailsEngine extends FakeEngine {
  @override
  AuditionVoice play(AuditionSource source, {double volume = 1}) {
    if (voices.isNotEmpty) throw StateError('second note failed');
    return super.play(source, volume: volume);
  }
}

Instrument recipe({
  String id = 'a',
  String name = 'A',
  List<String> tags = const [],
  int decayMs = 200,
}) => Instrument(
  id: id,
  name: name,
  tags: tags,
  harmonics: const [1, 0.5],
  attackMs: 2,
  decayMs: decayMs,
);

void main() {
  late FakeEngine engine;
  late List<double> renderedAt;

  Future<Float32List> render(Instrument instrument, double hz) async {
    renderedAt.add(hz);
    return Float32List.fromList([0, 0.5, -0.5, 0]);
  }

  EngineInstrumentAuditionRepository create({
    InstrumentRender? renderer,
    int cacheSize = 16,
  }) => EngineInstrumentAuditionRepository(
    engine,
    render: renderer ?? render,
    cacheSize: cacheSize,
  );

  setUp(() {
    engine = FakeEngine();
    renderedAt = [];
  });

  test('plays a rendered WAV after starting the engine', () async {
    final repository = create();
    expect(await repository.play(recipe(), [440]), isTrue);

    expect(engine.starts, 1);
    expect(engine.events, ['load audition-0', 'play audition-0']);
    expect(renderedAt, [440]);
    expect(repository.available.value, isTrue);
  });

  test('the engine gets a WAV file made from the rendered samples', () async {
    late Uint8List wav;
    final repository = EngineInstrumentAuditionRepository(
      CapturingEngine((bytes) => wav = bytes),
      render: render,
    );
    await repository.play(recipe(), [440]);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(wav.length, 44 + 4 * 2);
  });

  test('a single note plays at 0.8 volume to keep headroom', () async {
    final repository = create();
    await repository.play(recipe(), [440]);
    expect(engine.voices.single.volume, closeTo(0.8, 1e-9));
  });

  test('nothing is rendered or played for an empty list of notes', () async {
    final repository = create();
    expect(await repository.play(recipe(), const []), isFalse);
    expect(engine.starts, 0);
    expect(renderedAt, isEmpty);
    expect(engine.events, isEmpty);
  });

  group('chords', () {
    test(
      'every note is rendered at its own pitch and played together',
      () async {
        final repository = create();
        expect(await repository.play(recipe(), [261.63, 329.63, 392]), isTrue);

        expect(renderedAt..sort(), [261.63, 329.63, 392]);
        expect(engine.events.where((e) => e.startsWith('load')), hasLength(3));
        expect(engine.voices, hasLength(3));
      },
    );

    test('the notes share the volume so a chord does not clip', () async {
      final repository = create();
      await repository.play(recipe(), [261.63, 329.63, 392, 466.16]);
      for (final voice in engine.voices) {
        expect(voice.volume, closeTo(0.8 / 4, 1e-9));
      }
    });

    test('a note already rendered is reused by the next chord', () async {
      final repository = create();
      await repository.play(recipe(), [440]);
      await repository.play(recipe(), [440, 554.37]);
      expect(renderedAt, [440, 554.37]);
    });

    test(
      'stops voices already started when a later chord note fails',
      () async {
        engine = SecondPlayFailsEngine();
        final repository = create();

        expect(await repository.play(recipe(), [261.63, 329.63]), isFalse);
        expect(
          engine.events,
          containsAllInOrder(['play audition-0', 'stop audition-0']),
        );
      },
    );
  });

  group('cache', () {
    test(
      'an unchanged recipe at the same pitch is rendered and loaded once',
      () async {
        final repository = create();
        await repository.play(recipe(), [440]);
        await repository.play(recipe(), [440]);

        expect(renderedAt, [440]);
        expect(engine.events.where((e) => e.startsWith('load')), hasLength(1));
        expect(engine.events.where((e) => e.startsWith('play')), hasLength(2));
      },
    );

    test(
      'name, id and tags do not change the sound, so they do not re-render',
      () async {
        final repository = create();
        await repository.play(recipe(), [440]);
        await repository.play(
          recipe(id: 'other', name: 'Renamed', tags: ['click']),
          [440],
        );
        expect(renderedAt, [440]);
      },
    );

    test('a different pitch or a changed recipe is rendered again', () async {
      final repository = create();
      await repository.play(recipe(), [440]);
      await repository.play(recipe(), [880]);
      await repository.play(recipe(decayMs: 300), [440]);
      expect(renderedAt, [440, 880, 440]);
    });

    test('the oldest buffer is unloaded when the cache is full', () async {
      final repository = create(cacheSize: 2);
      await repository.play(recipe(), [200]);
      await repository.play(recipe(), [300]);
      await repository.play(recipe(), [400]);
      await Future<void>.delayed(Duration.zero);

      expect(engine.unloaded, ['audition-0']);
    });

    test('a recently used buffer is kept when the cache evicts', () async {
      final repository = create(cacheSize: 2);
      await repository.play(recipe(), [200]);
      await repository.play(recipe(), [300]);
      await repository.play(recipe(), [200]); // 200 is the most recent again
      await repository.play(recipe(), [400]);
      await Future<void>.delayed(Duration.zero);

      expect(engine.unloaded, ['audition-1']);
    });

    test(
      'keeps the sounding source until a replacement has rendered',
      () async {
        final replacement = Completer<Float32List>();
        final repository = create(
          cacheSize: 1,
          renderer: (instrument, hz) =>
              hz == 300 ? replacement.future : render(instrument, hz),
        );
        await repository.play(recipe(), [200]);

        final next = repository.play(recipe(), [300]);
        await Future<void>.delayed(Duration.zero);
        expect(engine.events, isNot(contains('unload audition-0')));

        replacement.complete(Float32List.fromList([0, 0.5, -0.5, 0]));
        expect(await next, isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(
          engine.events,
          containsAllInOrder([
            'load audition-1',
            'stop audition-0',
            'unload audition-0',
            'play audition-1',
          ]),
        );
      },
    );

    test(
      'a failed replacement render leaves the sounding source loaded',
      () async {
        final repository = create(
          cacheSize: 1,
          renderer: (instrument, hz) => hz == 300
              ? Future<Float32List>.error(StateError('render failed'))
              : render(instrument, hz),
        );
        await repository.play(recipe(), [200]);

        expect(await repository.play(recipe(), [300]), isFalse);
        expect(engine.events, isNot(contains('stop audition-0')));
        expect(engine.events, isNot(contains('unload audition-0')));
      },
    );

    test('a failed load is not cached', () async {
      final repository = create();
      engine.failLoad = true;
      expect(await repository.play(recipe(), [440]), isFalse);

      engine.failLoad = false;
      expect(await repository.play(recipe(), [440]), isTrue);
      expect(renderedAt, [
        440,
        440,
      ], reason: 'the failure must not stay cached');
    });
  });

  group('replacing and failing', () {
    test(
      'every sounding note is stopped before the next sound starts',
      () async {
        final repository = create();
        await repository.play(recipe(), [200, 300]);
        engine.events.clear();
        await repository.play(recipe(), [400]);

        expect(engine.events, [
          'load audition-2',
          'stop audition-0',
          'stop audition-1',
          'play audition-2',
        ]);
      },
    );

    test(
      'the newest request wins when an older one is still rendering',
      () async {
        final slow = Completer<Float32List>();
        final repository = create(
          renderer: (instrument, hz) =>
              hz == 220 ? slow.future : render(instrument, hz),
        );

        final first = repository.play(recipe(), [220]);
        final second = repository.play(recipe(), [330]);
        expect(await second, isTrue);
        slow.complete(Float32List.fromList([0, 0.1, 0]));

        expect(await first, isFalse, reason: 'superseded, so it must not play');
        expect(engine.voices, hasLength(1));
      },
    );

    test(
      'an engine that cannot start is reported, and a later try can recover',
      () async {
        final repository = create();
        engine.failStart = true;
        expect(await repository.play(recipe(), [440]), isFalse);
        expect(repository.available.value, isFalse);

        engine.failStart = false;
        expect(await repository.play(recipe(), [440]), isTrue);
        expect(repository.available.value, isTrue);
      },
    );

    test(
      'dispose stops the sound, unloads everything and shuts the engine down',
      () async {
        final repository = create();
        await repository.play(recipe(), [200, 300]);
        await repository.dispose();

        expect(engine.unloaded..sort(), ['audition-0', 'audition-1']);
        expect(engine.events.where((e) => e.startsWith('stop')), hasLength(2));
        expect(engine.disposed, isTrue);
      },
    );
  });
}
