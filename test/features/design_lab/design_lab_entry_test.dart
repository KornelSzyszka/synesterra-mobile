import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';

Future<void> _pumpApp(WidgetTester tester, {bool hideLab = false}) async {
  await tester.pumpWidget(
    SynesterraApp(
      instrumentLibrary: InMemoryInstrumentLibraryRepository(),
      instrumentAudition: NoopInstrumentAuditionRepository(),
      debugHideDesignLab: hideLab,
    ),
  );
}

void main() {
  testWidgets('a long press on the title opens the lab in a debug build', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.longPress(find.byKey(const Key('home-title')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('design-lab')), findsOneWidget);
  });

  // A release build cannot run under flutter_test (kDebugMode is const
  // true), so the release path is simulated with the test-only hook that can
  // only hide the lab; nothing can show it outside a debug build.
  testWidgets('without the debug gate there is no lab entry', (tester) async {
    await _pumpApp(tester, hideLab: true);

    await tester.longPress(find.byKey(const Key('home-title')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('design-lab')), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('design lab', caseSensitive: false)),
      findsNothing,
    );
  });
}
