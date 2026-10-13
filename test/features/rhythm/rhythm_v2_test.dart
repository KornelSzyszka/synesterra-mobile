import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/rhythm_settings_repository.dart';
import 'package:synesterra/features/rhythm/rhythm_view.dart';
import 'package:synesterra/features/rhythm/rhythm_view_model.dart';
import 'package:synesterra/shared/theme/ground_palette.dart';
import 'package:synesterra/shared/theme/surfaces.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/widgets/round_components.dart';

class _Repository implements RhythmSettingsRepository {
  RhythmSettings settings = RhythmSettings(
    tempoBpm: 120,
    layers: List.generate(
      4,
      (index) => RhythmLayerSettings(enabled: index == 0, beatsPerCycle: 4),
    ),
  );

  @override
  RhythmSettings read() => settings;

  @override
  void save(RhythmSettings value) => settings = value;
}

void main() {
  testWidgets('the rhythm screen follows the app default palette, Graphite', (
    tester,
  ) async {
    final viewModel = RhythmViewModel(repository: _Repository());
    addTearDown(viewModel.dispose);
    expect(
      RhythmView(viewModel: viewModel).palette,
      SynesterraPalette.graphite,
    );
  });

  testWidgets('layers are organic cards with labelled 48 dp round toggles', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    tester.view
      ..physicalSize = const Size(412, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final viewModel = RhythmViewModel(repository: _Repository());
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.graphite),
        home: RhythmView(viewModel: viewModel, onPaletteChanged: (_) {}),
      ),
    );

    // Four layers and the tempo.
    expect(find.byType(OrganicCard), findsNWidgets(5));
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      tester.getSemantics(find.byKey(const Key('layer-0-enabled'))),
      matchesSemantics(
        label: 'Layer 1',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester.binding.transientCallbackCount, 0);
    handle.dispose();
  });

  test('the steppers keep 4.5:1 on the organic cards in every palette', () {
    for (final palette in SynesterraPalette.values) {
      final tokens = SynesterraTokens.forPalette(palette);
      for (final aura in tokens.layerColors) {
        final surfaces = Surfaces(
          GroundPalette.of(tokens, GroundTone.dark, aura),
        );
        for (final fill in surfaces.fillSamples(SurfaceStyle.organic)) {
          // NumberStepper draws its label in tokens.muted and its icons in
          // tokens.text; the card text uses the surface's own roles.
          for (final text in [
            tokens.text,
            tokens.muted,
            surfaces.textOn(SurfaceStyle.organic),
            surfaces.mutedOn(SurfaceStyle.organic),
          ]) {
            expect(
              contrastRatio(text, fill),
              greaterThanOrEqualTo(4.5),
              reason: palette.name,
            );
          }
        }
      }
    }
  });
}
