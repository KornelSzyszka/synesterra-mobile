import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/instrument_library_repository.dart';
import 'package:synesterra/features/library/library_view.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra_core/synesterra_core.dart';

Instrument mine(String id, String name) => Instrument(
  id: id,
  name: name,
  fundamentalHz: 330,
  harmonics: const [1, 0.4, 0.2],
  attackMs: 3,
  decayMs: 150,
);

class UnreadableRepository extends InMemoryInstrumentLibraryRepository {
  @override
  ValueListenable<InstrumentLibrarySnapshot> get snapshot =>
      ValueNotifier(InstrumentLibrarySnapshot(unreadableCount: 2));
}

Future<void> pumpLibrary(
  WidgetTester tester,
  InstrumentLibraryRepository repository, {
  OpenInstrument? onOpen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.forest),
      home: LibraryView(
        instrumentLibrary: repository,
        onOpenInstrument: onOpen ?? (_, _) {},
      ),
    ),
  );
}

void main() {
  testWidgets(
    'an empty library explains itself and lists the factory presets',
    (tester) async {
      await pumpLibrary(tester, InMemoryInstrumentLibraryRepository());

      expect(
        find.text('No instruments yet. Save one from the Editor.'),
        findsOneWidget,
      );
      for (final preset in factoryInstruments) {
        expect(find.byKey(Key('factory-tile-${preset.id}')), findsOneWidget);
      }
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    },
  );

  testWidgets(
    'own instruments are listed by name, with the factory ones apart',
    (tester) async {
      await pumpLibrary(
        tester,
        InMemoryInstrumentLibraryRepository([
          mine('b', 'beta'),
          mine('a', 'Alpha'),
        ]),
      );

      expect(
        find.text('No instruments yet. Save one from the Editor.'),
        findsNothing,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('own-a'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('own-b'))).dy),
      );
      expect(find.text('330 Hz · E4 · 3 harmonics · 150 ms'), findsNWidgets(2));
    },
  );

  testWidgets(
    'tapping a tile opens it: in place for own, as a copy for factory',
    (tester) async {
      final opened = <(String, bool)>[];
      await pumpLibrary(
        tester,
        InMemoryInstrumentLibraryRepository([mine('a', 'Alpha')]),
        onOpen: (instrument, existing) => opened.add((instrument.id, existing)),
      );

      await tester.tap(find.byKey(const Key('own-a')));
      await tester.tap(find.byKey(const Key('factory-tile-factory-wood')));

      expect(opened, [('a', true), ('factory-wood', false)]);
    },
  );

  testWidgets('delete removes the instrument and Undo brings it back', (
    tester,
  ) async {
    final repository = InMemoryInstrumentLibraryRepository([
      mine('a', 'Alpha'),
    ]);
    await pumpLibrary(tester, repository);

    await tester.tap(find.byKey(const Key('delete-a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.snapshot.value.instruments, isEmpty);
    expect(find.byKey(const Key('own-a')), findsNothing);
    expect(find.text('Deleted "Alpha"'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();

    expect(repository.snapshot.value.instruments.single.id, 'a');
    expect(find.byKey(const Key('own-a')), findsOneWidget);
  });

  testWidgets('files that could not be read are announced, not hidden', (
    tester,
  ) async {
    await pumpLibrary(tester, UnreadableRepository());

    expect(
      find.text('2 stored files could not be read. They were left untouched.'),
      findsOneWidget,
    );
  });

  testWidgets('factory instruments cannot be deleted', (tester) async {
    await pumpLibrary(tester, InMemoryInstrumentLibraryRepository());
    expect(find.byTooltip('Delete Wood'), findsNothing);
  });

  testWidgets('from the library: open a preset, save it, find it in the list', (
    tester,
  ) async {
    final repository = InMemoryInstrumentLibraryRepository();
    await tester.pumpWidget(SynesterraApp(instrumentLibrary: repository));
    await tester.tap(find.byKey(const Key('home-library')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('factory-tile-factory-wood')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('instrument-name')))
          .controller!
          .text,
      'Wood',
    );

    await tester.tap(find.byKey(const Key('instrument-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pageBack();
    await tester.pumpAndSettle();

    final saved = repository.snapshot.value.instruments.single;
    expect(saved.name, 'Wood');
    expect(saved.id, isNot('factory-wood'));
    expect(find.byKey(Key('own-${saved.id}')), findsOneWidget);
  });

  testWidgets('opening an own instrument edits it in place', (tester) async {
    final repository = InMemoryInstrumentLibraryRepository([
      mine('a', 'Alpha'),
    ]);
    await tester.pumpWidget(SynesterraApp(instrumentLibrary: repository));
    await tester.tap(find.byKey(const Key('home-library')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('own-a')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('instrument-name')), 'Alpha 2');
    await tester.pump();
    await tester.tap(find.byKey(const Key('instrument-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final all = repository.snapshot.value.instruments;
    expect(all.single.id, 'a');
    expect(all.single.name, 'Alpha 2');
  });
}
