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
    return FakeVoice(source, volume);
  }

  @override
  Future<void> stop(AuditionVoice voice) async {
    events.add('stop ${(voice as FakeVoice).source.id}');
  }

  @override
  Future<void> unload(AuditionSource source) async {
    unloaded.add((source as FakeSource).id);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

Instrument recipe({
  String id = 'a',
  String name = 'A',
  double hz = 440,
  int decayMs = 200,
}) => Instrument(
  id: id,
  name: name,
  fundamentalHz: hz,
  harmonics: const [1, 0.5],
  attackMs: 2,
  decayMs: decayMs,
);

void main() {
  late FakeEngine engine;
  late int renders;

  Future<Float32List> render(Instrument instrument) async {
    renders++;
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
    renders = 0;
  });

  test(
    'plays a rendered WAV at reduced volume after starting the engine',
    () async {
      final repository = create();
      expect(await repository.play(recipe()), isTrue);

      expect(engine.starts, 1);
      expect(engine.events, ['load audition-0', 'play audition-0']);
      expect(renders, 1);
      expect(repository.available.value, isTrue);
    },
  );

  test('the engine gets a WAV file made from the rendered samples', () async {
    late Uint8List wav;
    final repository = EngineInstrumentAuditionRepository(
      _CapturingEngine((bytes) => wav = bytes),
      render: render,
    );
    await repository.play(recipe());
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(wav.length, 44 + 4 * 2);
  });

  test('plays at 0.8 volume to keep headroom', () async {
    final repository = create();
    await repository.play(recipe());
    expect(repository.volume, 0.8);
  });

  test(
    'an unchanged recipe is rendered and loaded once, even under another name',
    () async {
      final repository = create();
      await repository.play(recipe());
      await repository.play(recipe(id: 'other', name: 'Renamed'));
      await repository.play(recipe());

      expect(renders, 1);
      expect(engine.events.where((e) => e.startsWith('load')), hasLength(1));
      expect(engine.events.where((e) => e.startsWith('play')), hasLength(3));
    },
  );

  test('a changed recipe is rendered again', () async {
    final repository = create();
    await repository.play(recipe());
    await repository.play(recipe(decayMs: 300));
    expect(renders, 2);
  });

  test('the previous sound is stopped before the next one starts', () async {
    final repository = create();
    await repository.play(recipe());
    await repository.play(recipe(hz: 330));
    expect(engine.events, [
      'load audition-0',
      'play audition-0',
      'load audition-1',
      'stop audition-0',
      'play audition-1',
    ]);
  });

  test(
    'the newest request wins when an older one is still rendering',
    () async {
      final slow = Completer<Float32List>();
      final repository = create(
        renderer: (instrument) =>
            instrument.fundamentalHz == 220 ? slow.future : render(instrument),
      );

      final first = repository.play(recipe(hz: 220));
      final second = repository.play(recipe(hz: 330));
      expect(await second, isTrue);
      slow.complete(Float32List.fromList([0, 0.1, 0]));

      expect(await first, isFalse, reason: 'superseded, so it must not play');
      expect(engine.events.where((e) => e.startsWith('play')), hasLength(1));
    },
  );

  test(
    'an engine that cannot start is reported, and a later try can recover',
    () async {
      final repository = create();
      engine.failStart = true;
      expect(await repository.play(recipe()), isFalse);
      expect(repository.available.value, isFalse);

      engine.failStart = false;
      expect(await repository.play(recipe()), isTrue);
      expect(repository.available.value, isTrue);
    },
  );

  test('a failed load is not cached', () async {
    final repository = create();
    engine.failLoad = true;
    expect(await repository.play(recipe()), isFalse);

    engine.failLoad = false;
    expect(await repository.play(recipe()), isTrue);
    expect(renders, 2, reason: 'the failed attempt must not stay cached');
  });

  test('the oldest sound is unloaded when the cache is full', () async {
    final repository = create(cacheSize: 2);
    await repository.play(recipe(hz: 200));
    await repository.play(recipe(hz: 300));
    await repository.play(recipe(hz: 400));
    await Future<void>.delayed(Duration.zero);

    expect(engine.unloaded, ['audition-0']);
  });

  test('a recently used sound is kept when the cache evicts', () async {
    final repository = create(cacheSize: 2);
    await repository.play(recipe(hz: 200));
    await repository.play(recipe(hz: 300));
    await repository.play(recipe(hz: 200)); // 200 is the most recent again
    await repository.play(recipe(hz: 400));
    await Future<void>.delayed(Duration.zero);

    expect(engine.unloaded, ['audition-1']);
  });

  test(
    'dispose stops the sound, unloads everything and shuts the engine down',
    () async {
      final repository = create();
      await repository.play(recipe(hz: 200));
      await repository.play(recipe(hz: 300));
      await repository.dispose();

      expect(engine.unloaded..sort(), ['audition-0', 'audition-1']);
      expect(engine.disposed, isTrue);
    },
  );
}

class _CapturingEngine extends FakeEngine {
  _CapturingEngine(this.onLoad);

  final void Function(Uint8List) onLoad;

  @override
  Future<AuditionSource> load(String id, Uint8List wav) {
    onLoad(wav);
    return super.load(id, wav);
  }
}
