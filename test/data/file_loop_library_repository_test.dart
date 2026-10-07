import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/file_loop_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/data/repositories/loop.dart';
import 'package:synesterra/data/repositories/loop_library_repository.dart';
import 'package:synesterra/data/services/json_file_store.dart';

Loop loop(
  String id,
  String name, {
  int bpm = 90,
  List<int> hits = const [3, 2],
}) => Loop(
  id: id,
  name: name,
  document: simpleLoopDocument(
    bpm: bpm,
    cycleBeats: 4,
    layers: [
      for (final h in hits)
        LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: h),
    ],
  ),
);

void main() {
  late Directory directory;
  late FileLoopLibraryRepository repository;

  FileLoopLibraryRepository open() =>
      FileLoopLibraryRepository(JsonFileStore(directory));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('loops_test_');
    repository = open();
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  File file(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  List<String> names() =>
      directory.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  group('file repository', () {
    test('starts empty when the directory does not exist yet', () async {
      await directory.delete(recursive: true);
      await repository.load();
      expect(repository.snapshot.value.items, isEmpty);
      expect(repository.snapshot.value.unreadableCount, 0);
    });

    test('a saved loop survives a new repository (round trip)', () async {
      final original = loop('loop-1', 'Groove', hits: [5, 4, 3]);
      await repository.save(original);

      final reopened = open();
      await reopened.load();
      expect(reopened.snapshot.value.items, [original]);
      expect(names(), ['loop-1.json']);
    });

    test('rename is a save with the same id', () async {
      final original = loop('loop-1', 'Groove');
      await repository.save(original);
      await repository.save(original.copyWith(name: 'Renamed'));

      final reopened = open();
      await reopened.load();
      expect(reopened.snapshot.value.items.single.name, 'Renamed');
      expect(names(), ['loop-1.json']);
    });

    test('delete removes the file; saving again restores it (undo)', () async {
      final original = loop('loop-1', 'Groove');
      await repository.save(original);
      await repository.delete('loop-1');
      expect(repository.snapshot.value.items, isEmpty);
      expect(file('loop-1.json').existsSync(), isFalse);

      await repository.save(original);
      final reopened = open();
      await reopened.load();
      expect(reopened.snapshot.value.items, [original]);
      await repository.delete('never-existed');
    });

    test('list is sorted by name ignoring case', () async {
      await repository.save(loop('c', 'bell'));
      await repository.save(loop('a', 'Wood'));
      await repository.save(loop('b', 'Alpha'));
      expect(repository.snapshot.value.items.map((l) => l.name), [
        'Alpha',
        'bell',
        'Wood',
      ]);
    });

    test('factory loops are read-only', () async {
      final factory = factoryLoops.first;
      expect(() => repository.save(factory), throwsArgumentError);
      expect(() => repository.delete(factory.id), throwsArgumentError);
      expect(directory.listSync(), isEmpty);
    });

    test('corrupt, invalid, misnamed, duplicate and factory files are '
        'skipped, counted and left untouched', () async {
      await repository.save(loop('good', 'Good'));
      final good = jsonEncode(loop('good', 'Good').toJson());
      final contents = <String, Object>{
        'broken.json': '{ not json',
        'invalid.json': jsonEncode({
          ...loop('invalid', 'X').toJson(),
          'extra': true,
        }),
        'bytes.json': [0xff, 0xfe, 0xfd],
        // The content says "good", the name says "other".
        'other.json': good,
        'factory-loop-3-2.json': jsonEncode(factoryLoops.first.toJson()),
        'session.json': jsonEncode(loop('session', 'S').document.toJson()),
      };
      for (final MapEntry(:key, :value) in contents.entries) {
        if (value is String) {
          await file(key).writeAsString(value);
        } else {
          await file(key).writeAsBytes(value as List<int>);
        }
      }
      final before = {
        for (final name in contents.keys) name: await file(name).readAsBytes(),
      };

      final reopened = open();
      await reopened.load();
      expect(reopened.snapshot.value.items.map((l) => l.id), ['good']);
      expect(reopened.snapshot.value.unreadableCount, contents.length);

      // Saving and deleting other items never touches the unreadable files.
      await reopened.save(loop('new', 'New'));
      await reopened.delete('good');
      for (final name in contents.keys) {
        expect(await file(name).readAsBytes(), before[name], reason: name);
      }
      expect(reopened.snapshot.value.unreadableCount, contents.length);
    });

    test('a leftover temporary file is ignored', () async {
      await repository.save(loop('a', 'A'));
      await file('b.json.tmp').writeAsString('half written');

      final reopened = open();
      await reopened.load();
      expect(reopened.snapshot.value.items, hasLength(1));
      expect(reopened.snapshot.value.unreadableCount, 0);
    });

    test('a v2 session loads and is not rewritten by loading', () async {
      await directory.create(recursive: true);
      final json = loop('old', 'Old').toJson();
      final session = jsonDecode(jsonEncode(json['session'])) as Map;
      session['version'] = 2;
      for (final scene in session['scenes'] as List) {
        for (final layer in (scene as Map)['layers'] as List) {
          (layer as Map)
            ..remove('instrumentId')
            ..remove('pitch')
            ..['sound'] = 'wood';
        }
      }
      final text = jsonEncode({...json, 'session': session});
      await file('old.json').writeAsString(text);

      final reopened = open();
      await reopened.load();
      final loaded = reopened.snapshot.value.items.single;
      expect(
        loaded.document.scenes.first.layers.first.instrumentId,
        'factory-wood',
      );
      expect(await file('old.json').readAsString(), text);
    });

    test('overlapping saves of one id leave one complete file with the last '
        'version', () async {
      final saves = [
        for (var bpm = 60; bpm < 80; bpm++)
          repository.save(loop('same', 'Same', bpm: bpm)),
      ];
      await Future.wait(saves);

      expect(names(), ['same.json']);
      expect(repository.snapshot.value.items.single.bpm, 79);
      final reopened = open();
      await reopened.load();
      expect(reopened.snapshot.value.items.single.bpm, 79);
    });

    test('a delete issued after a save wins even when they overlap', () async {
      final save = repository.save(loop('x', 'X'));
      final delete = repository.delete('x');
      await Future.wait([save, delete]);

      expect(names(), isEmpty);
      expect(repository.snapshot.value.items, isEmpty);
    });

    test('notifies listeners on save and delete', () async {
      var calls = 0;
      repository.snapshot.addListener(() => calls++);
      await repository.save(loop('a', 'A'));
      await repository.delete('a');
      expect(calls, 2);
    });
  });

  group('lookup', () {
    test('finds factory and own loops by id, null when missing', () async {
      await repository.save(loop('mine', 'Mine'));
      final snapshot = repository.snapshot.value;
      expect(findLoop(snapshot, 'mine')!.name, 'Mine');
      expect(findLoop(snapshot, factoryLoops.first.id), factoryLoops.first);
      expect(findLoop(snapshot, 'gone'), isNull);
    });
  });

  group('in-memory repository', () {
    test(
      'behaves like the file one for save, rename, delete and order',
      () async {
        final memory = InMemoryLoopLibraryRepository([loop('b', 'Beta')]);
        await memory.save(loop('a', 'alpha'));
        await memory.save(loop('b', 'Beta', bpm: 120));
        expect(memory.snapshot.value.items.map((l) => l.name), [
          'alpha',
          'Beta',
        ]);
        expect(memory.snapshot.value.items.last.bpm, 120);
        await memory.delete('a');
        expect(memory.snapshot.value.items, hasLength(1));
        expect(() => memory.save(factoryLoops.first), throwsArgumentError);
        expect(() => memory.delete(factoryLoops.first.id), throwsArgumentError);
      },
    );
  });
}
