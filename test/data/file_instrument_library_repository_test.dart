import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/file_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/services/instrument_file_store.dart';
import 'package:synesterra_core/synesterra_core.dart';

Instrument instrument(String id, String name, {int decayMs = 200}) =>
    Instrument(
      id: id,
      name: name,
      harmonics: const [1, 0.5],
      attackMs: 2,
      decayMs: decayMs,
    );

void main() {
  late Directory directory;
  late FileInstrumentLibraryRepository repository;

  FileInstrumentLibraryRepository open() =>
      FileInstrumentLibraryRepository(InstrumentFileStore(directory));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('instruments_test_');
    repository = open();
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  File file(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  group('file repository', () {
    test('starts empty when the directory does not exist yet', () async {
      await directory.delete(recursive: true);
      await repository.load();
      expect(repository.snapshot.value.instruments, isEmpty);
      expect(repository.snapshot.value.unreadableCount, 0);
    });

    test('a saved instrument survives a new repository (round trip)', () async {
      final original = instrument('a-1', 'Soft');
      await repository.save(original);

      final reopened = open();
      await reopened.load();
      expect(reopened.snapshot.value.instruments, [original]);
    });

    test('saving the same id replaces the instrument', () async {
      await repository.save(instrument('a-1', 'Soft'));
      await repository.save(instrument('a-1', 'Soft', decayMs: 900));

      final reopened = open();
      await reopened.load();
      expect(reopened.snapshot.value.instruments, hasLength(1));
      expect(reopened.snapshot.value.instruments.single.decayMs, 900);
    });

    test('delete removes the file and the instrument', () async {
      await repository.save(instrument('a-1', 'Soft'));
      await repository.delete('a-1');
      expect(repository.snapshot.value.instruments, isEmpty);
      expect(file('a-1.json').existsSync(), isFalse);
      await repository.delete('never-existed');
    });

    test('list is sorted by name ignoring case', () async {
      await repository.save(instrument('c', 'bell'));
      await repository.save(instrument('a', 'Wood'));
      await repository.save(instrument('b', 'Alpha'));
      expect(repository.snapshot.value.instruments.map((i) => i.name), [
        'Alpha',
        'bell',
        'Wood',
      ]);
    });

    test('notifies listeners on save and delete', () async {
      var calls = 0;
      repository.snapshot.addListener(() => calls++);
      await repository.save(instrument('a', 'A'));
      await repository.delete('a');
      expect(calls, 2);
    });

    test('corrupted, invalid and duplicate files are skipped, counted and '
        'left on disk', () async {
      await repository.save(instrument('good', 'Good'));
      await file('broken.json').writeAsString('{ not json');
      await file('invalid.json').writeAsString(
        jsonEncode({...instrument('x', 'X').toJson(), 'decayMs': 1}),
      );
      await file('bytes.json').writeAsBytes([0xff, 0xfe, 0xfd]);
      await file('copy.json')
          .writeAsString(jsonEncode(instrument('good', 'Good copy').toJson()));

      final reopened = open();
      await reopened.load();
      expect(reopened.snapshot.value.instruments.map((i) => i.id), ['good']);
      expect(reopened.snapshot.value.unreadableCount, 4);
      for (final name in ['broken', 'invalid', 'bytes', 'copy']) {
        expect(file('$name.json').existsSync(), isTrue, reason: name);
      }
    });

    test('a leftover temporary file is ignored', () async {
      await repository.save(instrument('a', 'A'));
      await file('b.json.tmp').writeAsString('half written');

      final reopened = open();
      await reopened.load();
      expect(reopened.snapshot.value.instruments, hasLength(1));
      expect(reopened.snapshot.value.unreadableCount, 0);
    });

    test('saving does not leave a temporary file behind', () async {
      await repository.save(instrument('a', 'A'));
      final names = directory.listSync().map((e) => e.uri.pathSegments.last);
      expect(names, ['a.json']);
    });
  });

  group('in-memory repository', () {
    test(
      'behaves like the file one for save, replace, delete and order',
      () async {
        final memory = InMemoryInstrumentLibraryRepository([
          instrument('b', 'Beta'),
        ]);
        await memory.save(instrument('a', 'alpha'));
        await memory.save(instrument('b', 'Beta', decayMs: 300));
        expect(memory.snapshot.value.instruments.map((i) => i.name), [
          'alpha',
          'Beta',
        ]);
        expect(memory.snapshot.value.instruments.last.decayMs, 300);
        await memory.delete('a');
        expect(memory.snapshot.value.instruments, hasLength(1));
      },
    );
  });

  group('files written before tags and without a pitch', () {
    test(
      'a version 1 file (with a pitch) still loads, without the pitch',
      () async {
        await directory.create(recursive: true);
        await file('old.json').writeAsString(
          jsonEncode({
            'version': 1,
            'id': 'old',
            'name': 'Old click',
            'fundamentalHz': 800.0,
            'harmonics': [1.0, 0.5],
            'envelope': {'attackMs': 1, 'decayMs': 70},
            'eq': {'lowDb': 0.0, 'midDb': 0.0, 'highDb': 0.0},
          }),
        );

        final reopened = open();
        await reopened.load();
        expect(reopened.snapshot.value.instruments.single.name, 'Old click');
        expect(reopened.snapshot.value.instruments.single.tags, isEmpty);
        expect(reopened.snapshot.value.unreadableCount, 0);
      },
    );

    test(
      'loading does not rewrite the old file; saving writes version 2',
      () async {
        await directory.create(recursive: true);
        final old = jsonEncode({
          'version': 1,
          'id': 'old',
          'name': 'Old click',
          'fundamentalHz': 800.0,
          'harmonics': [1.0, 0.5],
          'envelope': {'attackMs': 1, 'decayMs': 70},
          'eq': {'lowDb': 0.0, 'midDb': 0.0, 'highDb': 0.0},
        });
        await file('old.json').writeAsString(old);

        final reopened = open();
        await reopened.load();
        expect(await file('old.json').readAsString(), old);

        await reopened.save(
          reopened.snapshot.value.instruments.single.copyWith(tags: ['click']),
        );
        final written =
            jsonDecode(await file('old.json').readAsString()) as Map;
        expect(written['version'], 2);
        expect(written['tags'], ['click']);
        expect(written.containsKey('fundamentalHz'), isFalse);
      },
    );

    test('tags survive a save and load', () async {
      await repository.save(
        instrument('a', 'A').copyWith(tags: ['bell', 'metal']),
      );
      final reopened = open();
      await reopened.load();
      expect(reopened.snapshot.value.instruments.single.tags, [
        'bell',
        'metal',
      ]);
    });
  });
}
