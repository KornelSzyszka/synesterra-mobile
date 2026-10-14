import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/design_lab/design_lab_view.dart';
import 'package:synesterra/shared/living_blobs/living_field.dart';
import 'package:synesterra/shared/living_blobs/living_surface.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra_core/synesterra_core.dart';

Future<void> _pumpLab(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(412 * 3, 3400 * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.graphite),
      home: const DesignLabView(),
    ),
  );
  await tester.pump();
}

/// The gallery shows up to four factory instruments.
final _cards = factoryInstruments.take(4).length;

void main() {
  setUp(() => livingBlobsEnabled.value = true);
  tearDown(() => livingBlobsEnabled.value = true);

  testWidgets('the lab compares flat and living blobs, with the frame time', (
    tester,
  ) async {
    await _pumpLab(tester);
    expect(find.byKey(const Key('lab-living-gallery')), findsOneWidget);
    expect(find.byKey(const Key('lab-frame-timing')), findsOneWidget);
    // Living is the default.
    expect(find.byType(LivingBlob), findsNWidgets(_cards));

    await tester.tap(find.byKey(const ValueKey('lab-blobs-flat')));
    await tester.pump();
    expect(livingBlobsEnabled.value, isFalse);
    expect(find.byType(LivingBlob), findsNothing);

    await tester.tap(find.byKey(const ValueKey('lab-blobs-living')));
    await tester.pump();
    expect(livingBlobsEnabled.value, isTrue);
    expect(find.byType(LivingBlob), findsNWidgets(_cards));

    // The lab's gallery never settles, so its frame time can be read.
    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 16));
    final field = tester.state<LivingFieldState>(
      find.descendant(
        of: find.byKey(const Key('lab-living-gallery')),
        matching: find.byType(LivingField),
      ),
    );
    expect(field.isTicking, isTrue);
  });
}
