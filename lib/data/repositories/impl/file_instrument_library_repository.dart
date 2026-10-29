import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../services/instrument_file_store.dart';
import '../instrument_library_repository.dart';
import '../library_item.dart';

class FileInstrumentLibraryRepository implements InstrumentLibraryRepository {
  FileInstrumentLibraryRepository(this._store);

  final InstrumentFileStore _store;
  final _snapshot = ValueNotifier(InstrumentLibrarySnapshot());

  @override
  ValueListenable<InstrumentLibrarySnapshot> get snapshot => _snapshot;

  @override
  Future<void> load() async {
    final byId = <String, Instrument>{};
    var unreadable = 0;
    for (final file in await _store.readAll()) {
      final text = file.text;
      if (text == null) {
        unreadable++;
        continue;
      }
      try {
        final instrument = Instrument.fromJson(jsonDecode(text));
        // A reserved id would shadow a built-in instrument: keep the file,
        // do not show it.
        if (isFactoryId(instrument.id)) {
          unreadable++;
          continue;
        }
        // A second file with the same id is kept on disk but not shown.
        if (byId.containsKey(instrument.id)) {
          unreadable++;
        } else {
          byId[instrument.id] = instrument;
        }
      } on FormatException {
        unreadable++;
      }
    }
    _publish(byId.values, unreadable);
  }

  @override
  Future<void> save(Instrument instrument) async {
    checkInstrumentWritable(instrument.id);
    await _store.write(instrument.id, jsonEncode(instrument.toJson()));
    _publish([
      ..._snapshot.value.instruments.where((i) => i.id != instrument.id),
      instrument,
    ], _snapshot.value.unreadableCount);
  }

  @override
  Future<void> delete(String id) async {
    await _store.remove(id);
    _publish(
      _snapshot.value.instruments.where((i) => i.id != id),
      _snapshot.value.unreadableCount,
    );
  }

  void _publish(Iterable<Instrument> instruments, int unreadable) {
    _snapshot.value = InstrumentLibrarySnapshot(
      instruments: instruments.toList()..sort(compareInstrumentNames),
      unreadableCount: unreadable,
    );
  }
}
