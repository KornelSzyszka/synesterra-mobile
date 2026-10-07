import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/file_loop_library_repository.dart';
import 'package:synesterra/data/repositories/loop.dart';
import 'package:synesterra/data/services/json_file_store.dart';

enum Fault { none, temporaryWrite, replace }

/// Fails one step of the atomic write, as a full disk or a locked target
/// would. A failing temporary write leaves a half-written temporary file
/// behind first, as a crash in the middle of writing would.
class FaultyStore extends JsonFileStore {
  FaultyStore(super.directory);

  Fault fault = Fault.none;

  @override
  Future<void> writeTemporary(File temporary, String text) async {
    if (fault == Fault.temporaryWrite) {
      await temporary.writeAsString(text.substring(0, text.length ~/ 2));
      throw const FileSystemException('disk full (injected)');
    }
    await super.writeTemporary(temporary, text);
  }

  @override
  Future<void> replaceTarget(File temporary, String targetPath) async {
    if (fault == Fault.replace) {
      throw FileSystemException('rename failed (injected)', targetPath);
    }
    await super.replaceTarget(temporary, targetPath);
  }
}

Loop loop(int bpm) => Loop(
  id: 'loop-1',
  name: 'Groove',
  document: simpleLoopDocument(
    bpm: bpm,
    cycleBeats: 4,
    layers: const [
      LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: 3),
      LoopLayerSpec(instrumentId: 'factory-bell', pitch: 76, hits: 2),
    ],
  ),
);

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('json_store_test_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  File target() => File('${directory.path}${Platform.pathSeparator}a.json');

  List<String> names() =>
      directory.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  for (final fault in [Fault.temporaryWrite, Fault.replace]) {
    test('when the ${fault.name} step fails, the previous file stays '
        'byte-identical and no temporary file is left', () async {
      final store = FaultyStore(directory);
      await store.write('a', '{"v":1}');
      final before = await target().readAsBytes();

      store.fault = fault;
      await expectLater(
        store.write('a', '{"v":2,"long":"${'x' * 100}"}'),
        throwsA(isA<FileSystemException>()),
      );

      expect(await target().readAsBytes(), before);
      expect(names(), ['a.json']);

      // The next write after the failure still succeeds completely.
      store.fault = Fault.none;
      await store.write('a', '{"v":3}');
      expect(await target().readAsString(), '{"v":3}');
      expect(names(), ['a.json']);
    });

    test('a failed save (${fault.name}) keeps the previous loop on disk and in '
        'the snapshot', () async {
      final store = FaultyStore(directory);
      final repository = FileLoopLibraryRepository(store);
      final original = loop(90);
      await repository.save(original);

      store.fault = fault;
      await expectLater(
        repository.save(loop(140)),
        throwsA(isA<FileSystemException>()),
      );
      expect(repository.snapshot.value.items, [original]);

      final reopened = FileLoopLibraryRepository(JsonFileStore(directory));
      await reopened.load();
      expect(reopened.snapshot.value.items, [original]);
      expect(reopened.snapshot.value.unreadableCount, 0);
    });
  }

  test('a failed first write leaves nothing behind', () async {
    final store = FaultyStore(directory)..fault = Fault.temporaryWrite;
    await expectLater(
      store.write('a', '{"v":1}'),
      throwsA(isA<FileSystemException>()),
    );
    expect(names(), isEmpty);
  });

  test('an id outside the id rule never becomes a path', () {
    final store = JsonFileStore(directory);
    for (final id in ['../x', r'a\b', '', 'a.b']) {
      expect(() => store.write(id, '{}'), throwsArgumentError, reason: id);
      expect(() => store.remove(id), throwsArgumentError, reason: id);
    }
  });
}
