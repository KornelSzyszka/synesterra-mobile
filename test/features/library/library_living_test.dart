import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_arrangement_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/features/library/library_view.dart';
import 'package:synesterra/shared/living_blobs/living_field.dart';
import 'package:synesterra/shared/living_blobs/living_surface.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra_core/synesterra_core.dart';

void main() {
  testWidgets('opening a library of 30 instruments never has more than the '
      'cap of cards following the clock, entrance included', (tester) async {
    livingBlobsEnabled.value = true;
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.graphite),
        home: LibraryView(
          instrumentLibrary: InMemoryInstrumentLibraryRepository([
            for (var i = 0; i < 30; i++)
              Instrument(
                id: 'i$i',
                name: 'Instrument $i',
                harmonics: const [1, .4],
                attackMs: 3,
                decayMs: 150,
              ),
          ]),
          loopLibrary: InMemoryLoopLibraryRepository(),
          arrangementLibrary: InMemoryArrangementLibraryRepository(),
          onOpenInstrument: (_, _) {},
          onOpenLoop: (_, _) {},
          onOpenArrangement: (_) {},
        ),
      ),
    );
    var most = 0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final listening = tester
          .stateList<LivingBlobState>(find.byType(LivingBlob))
          .where((b) => b.listening)
          .length;
      if (listening > most) most = listening;
    }
    expect(most, lessThanOrEqualTo(maxAnimatedBlobs));
    await tester.pumpAndSettle();
  });
}
