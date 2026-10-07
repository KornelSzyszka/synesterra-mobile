import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/arrangement_library_repository.dart';
import 'package:synesterra/data/repositories/impl/file_arrangement_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_arrangement_library_repository.dart';
import 'package:synesterra/data/repositories/interim_arrangement.dart';
import 'package:synesterra/data/services/json_file_store.dart';

InterimArrangement arrangement(String id, String name, {int repeats = 2}) =>
    InterimArrangement(
      id: id,
      name: name,
      sections: [
        InterimArrangementSection(loopId: 'factory-loop-3-2', repeats: repeats),
        InterimArrangementSection(loopId: 'loop-x', repeats: 1),
      ],
    );

void main() {
  late Directory directory;
  late FileArrangementLibraryRepository repository;

  FileArrangementLibraryRepository open() =>
      FileArrangementLibraryRepository(JsonFileStore(directory));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('arrangements_test_');
    repository = open();
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  File file(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  List<String> names() =>
      directory.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('starts empty when the directory does not exist yet', () async {
    await directory.delete(recursive: true);
    await repository.load();
    expect(repository.snapshot.value.items, isEmpty);
  });

  test('round trip, rename and delete', () async {
    final original = arrangement('arr-1', 'Song');
    await repository.save(original);
    var reopened = open();
    await reopened.load();
    expect(reopened.snapshot.value.items, [original]);

    await reopened.save(original.copyWith(name: 'Tune'));
    reopened = open();
    await reopened.load();
    expect(reopened.snapshot.value.items.single.name, 'Tune');

    await reopened.delete('arr-1');
    expect(reopened.snapshot.value.items, isEmpty);
    expect(names(), isEmpty);
  });

  test('corrupt, invalid and misnamed files are skipped, counted and left '
      'untouched', () async {
    await directory.create(recursive: true);
    final contents = {
      'broken.json': '[',
      'invalid.json': jsonEncode({
        ...arrangement('invalid', 'X').toJson(),
        'sections': [],
      }),
      'misnamed.json': jsonEncode(arrangement('other', 'Other').toJson()),
    };
    for (final MapEntry(:key, :value) in contents.entries) {
      await file(key).writeAsString(value);
    }
    await repository.save(arrangement('ok', 'Ok'));

    final reopened = open();
    await reopened.load();
    expect(reopened.snapshot.value.items.map((a) => a.id), ['ok']);
    expect(reopened.snapshot.value.unreadableCount, 3);
    await reopened.save(arrangement('more', 'More'));
    for (final MapEntry(:key, :value) in contents.entries) {
      expect(await file(key).readAsString(), value, reason: key);
    }
  });

  test('overlapping saves of one id keep the last version', () async {
    await Future.wait([
      for (var repeats = 1; repeats <= 20; repeats++)
        repository.save(arrangement('same', 'Same', repeats: repeats)),
    ]);
    expect(names(), ['same.json']);
    final reopened = open();
    await reopened.load();
    expect(reopened.snapshot.value.items.single.sections.first.repeats, 20);
    expect(repository.snapshot.value.items.single.sections.first.repeats, 20);
  });

  test('in-memory repository saves, replaces, deletes and sorts', () async {
    final memory = InMemoryArrangementLibraryRepository([
      arrangement('b', 'Beta'),
    ]);
    await memory.save(arrangement('a', 'alpha'));
    await memory.save(arrangement('b', 'Beta', repeats: 9));
    expect(memory.snapshot.value.items.map((a) => a.name), ['alpha', 'Beta']);
    expect(memory.snapshot.value.items.last.sections.first.repeats, 9);
    await memory.delete('a');
    expect(memory.snapshot.value.items, hasLength(1));
  });

  test('the abstract type is what the app sees', () {
    ArrangementLibraryRepository abstract = repository;
    expect(abstract.snapshot.value.unreadableCount, 0);
  });
}
