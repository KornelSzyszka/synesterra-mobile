import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/rhythm_settings_repository.dart';
import 'package:synesterra/features/rhythm/rhythm_view.dart';
import 'package:synesterra/features/rhythm/rhythm_view_model.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/widgets/design_components.dart';

class FakeRhythmSettingsRepository implements RhythmSettingsRepository {
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
  testWidgets('screen shows numbered layers and updates enabled controls', (
    tester,
  ) async {
    final repository = FakeRhythmSettingsRepository();
    final viewModel = RhythmViewModel(repository: repository);
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.forest),
        home: RhythmView(viewModel: viewModel),
      ),
    );

    expect(find.text('Warstwy rytmu'), findsOneWidget);
    expect(find.byType(LayerChip), findsNWidgets(4));
    expect(find.text('Layer 4'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);

    final offLayerStepper = find.byKey(const Key('layer-1-beats'));
    await tester.tap(
      find.descendant(
        of: offLayerStepper,
        matching: find.byTooltip('Increase beats / cycle'),
      ),
    );
    await tester.pump();
    expect(repository.settings.layers[1].enabled, isFalse);
    expect(repository.settings.layers[1].beatsPerCycle, 5);

    await tester.tap(find.byKey(const Key('layer-0-enabled')));
    await tester.pump();
    expect(repository.settings.layers.first.enabled, isFalse);
    await tester.tap(find.byKey(const Key('layer-0-enabled')));
    await tester.pump();
    expect(repository.settings.layers.first.enabled, isTrue);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('layer-0-beats')),
        matching: find.byTooltip('Increase beats / cycle'),
      ),
    );
    await tester.pump();
    expect(repository.settings.layers.first.beatsPerCycle, 5);

    await tester.ensureVisible(find.byKey(const Key('tempo-stepper')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('tempo-stepper')),
        matching: find.byTooltip('Increase BPM'),
      ),
    );
    await tester.pump();
    expect(repository.settings.tempoBpm, 121);
  });
}
