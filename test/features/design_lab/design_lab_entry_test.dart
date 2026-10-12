import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';
import 'package:synesterra/features/design_lab/lab_motion.dart';

Future<void> _pumpApp(WidgetTester tester, {bool? designLab}) async {
  await tester.pumpWidget(
    SynesterraApp(
      instrumentLibrary: InMemoryInstrumentLibraryRepository(),
      instrumentAudition: NoopInstrumentAuditionRepository(),
      designLab: designLab,
    ),
  );
}

void main() {
  test('the lab is available in debug builds only', () {
    expect(designLabAvailable(debugBuild: true), isTrue);
    expect(designLabAvailable(debugBuild: false), isFalse);
  });

  testWidgets('a long press on the title opens the lab in a debug build', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.longPress(find.byKey(const Key('home-title')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('design-lab')), findsOneWidget);
  });

  testWidgets('a release build has no lab entry', (tester) async {
    await _pumpApp(tester, designLab: false);

    await tester.longPress(find.byKey(const Key('home-title')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('design-lab')), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('design lab', caseSensitive: false)),
      findsNothing,
    );
  });
}
