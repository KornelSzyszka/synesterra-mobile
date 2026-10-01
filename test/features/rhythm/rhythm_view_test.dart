import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/rhythm_settings_repository.dart';
import 'package:synesterra/features/rhythm/rhythm_view.dart';
import 'package:synesterra/features/rhythm/rhythm_view_model.dart';

class FakeRhythmSettingsRepository implements RhythmSettingsRepository {
  RhythmSettings settings = RhythmSettings(
    tempoBpm: 120,
    layers: List.generate(
      4,
      (_) => RhythmLayerSettings(enabled: false, beatsPerCycle: 4),
    ),
  );

  @override
  RhythmSettings read() => settings;

  @override
  void save(RhythmSettings value) => settings = value;
}

void main() {
  testWidgets('renders four layers and sends control changes to view model', (
    tester,
  ) async {
    final repository = FakeRhythmSettingsRepository();
    final viewModel = RhythmViewModel(repository: repository);
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      MaterialApp(home: RhythmView(viewModel: viewModel)),
    );

    expect(find.text('Tempo: 120 BPM'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(4));
    expect(find.text('Layer 4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('layer-0-enabled')));
    await tester.pump();
    expect(repository.settings.layers.first.enabled, isTrue);

    await tester.drag(
      find.byKey(const Key('tempo-slider')),
      const Offset(150, 0),
    );
    await tester.pump();
    expect(repository.settings.tempoBpm, greaterThan(120));

    await tester.drag(
      find.byKey(const Key('layer-0-beats')),
      const Offset(100, 0),
    );
    await tester.pump();
    expect(repository.settings.layers.first.beatsPerCycle, greaterThan(4));
  });
}
