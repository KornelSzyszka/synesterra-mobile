import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';

void main() {
  test('graphite is a neutral, slightly cool dark grey with the icon gold', () {
    const graphite = SynesterraTokens.graphite;
    expect(SynesterraTokens.forPalette(SynesterraPalette.graphite), graphite);
    // Neutral: the channels of the ground stay within a few steps, blue a
    // touch higher (cool), and it is darker than its surface.
    for (final color in [graphite.background, graphite.surface]) {
      final r = (color.r * 255).round();
      final g = (color.g * 255).round();
      final b = (color.b * 255).round();
      expect(b - r, inInclusiveRange(1, 8), reason: '$color');
      expect((g - r).abs(), lessThanOrEqualTo(4), reason: '$color');
    }
    expect(
      graphite.background.computeLuminance(),
      lessThan(graphite.surface.computeLuminance()),
    );
    // The launcher icon's gold, so the app and the icon belong together.
    expect(graphite.accent, const Color(0xffe4b46a));
    // Layer colours are data colours and never change between palettes.
    expect(graphite.layerColors, SynesterraTokens.forest.layerColors);
  });

  testWidgets('the app starts on graphite and lists it first in the menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      SynesterraApp(
        instrumentLibrary: InMemoryInstrumentLibraryRepository(),
        instrumentAudition: NoopInstrumentAuditionRepository(),
      ),
    );
    final context = tester.element(find.byKey(const Key('home-title')));
    expect(SynesterraTokens.of(context), SynesterraTokens.graphite);

    await tester.tap(find.byTooltip('Choose palette'));
    await tester.pumpAndSettle();
    final items = tester
        .widgetList<PopupMenuItem<SynesterraPalette>>(
          find.byType(PopupMenuItem<SynesterraPalette>),
        )
        .map((item) => item.value)
        .toList();
    expect(items, [
      SynesterraPalette.graphite,
      SynesterraPalette.forest,
      SynesterraPalette.autumn,
      SynesterraPalette.highContrast,
    ]);

    // The other palettes stay available.
    await tester.tap(find.text('Forest'));
    await tester.pumpAndSettle();
    expect(
      SynesterraTokens.of(tester.element(find.byKey(const Key('home-title')))),
      SynesterraTokens.forest,
    );
  });
}
