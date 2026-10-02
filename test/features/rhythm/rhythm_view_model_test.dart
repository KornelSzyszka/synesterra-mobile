import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/rhythm_settings_repository.dart';
import 'package:synesterra/features/rhythm/rhythm_view_model.dart';

class FakeRhythmSettingsRepository implements RhythmSettingsRepository {
  RhythmSettings settings = RhythmSettings(
    tempoBpm: 120,
    layers: List.generate(
      4,
      (_) => RhythmLayerSettings(enabled: false, beatsPerCycle: 4),
    ),
  );
  int saveCount = 0;

  @override
  RhythmSettings read() => settings;

  @override
  void save(RhythmSettings value) {
    settings = value;
    saveCount++;
  }
}

void main() {
  test('settings use value equality', () {
    final layer = RhythmLayerSettings(enabled: true, beatsPerCycle: 4);
    expect(layer, equals(RhythmLayerSettings(enabled: true, beatsPerCycle: 4)));
    expect(
      layer.hashCode,
      equals(RhythmLayerSettings(enabled: true, beatsPerCycle: 4).hashCode),
    );
    final settings = RhythmSettings(
      tempoBpm: 120,
      layers: List.generate(4, (_) => layer),
    );
    expect(
      settings,
      equals(
        RhythmSettings(
          tempoBpm: 120,
          layers: List.generate(
            4,
            (_) => RhythmLayerSettings(enabled: true, beatsPerCycle: 4),
          ),
        ),
      ),
    );
  });

  test('settings reject values outside the screen contract', () {
    expect(
      () => RhythmLayerSettings(enabled: true, beatsPerCycle: 0),
      throwsRangeError,
    );
    expect(() => RhythmSettings(tempoBpm: 301, layers: []), throwsRangeError);
    expect(
      () => RhythmSettings(tempoBpm: 120, layers: []),
      throwsArgumentError,
    );
  });

  test('commands persist immutable state and notify listeners', () async {
    final repository = FakeRhythmSettingsRepository();
    final viewModel = RhythmViewModel(repository: repository);
    final oldState = viewModel.state;
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    await viewModel.setTempo.execute(300);
    await viewModel.setLayerEnabled.execute(
      const RhythmLayerEnabledCommand(1, true),
    );
    await viewModel.setLayerBeats.execute(const RhythmLayerBeatsCommand(1, 16));

    expect(viewModel.state.tempoBpm, 300);
    expect(viewModel.state.layers[1].enabled, isTrue);
    expect(viewModel.state.layers[1].beatsPerCycle, 16);
    expect(repository.settings, same(viewModel.state));
    expect(repository.saveCount, 3);
    expect(notifications, 3);
    expect(oldState.tempoBpm, 120);
    expect(oldState.layers[1].enabled, isFalse);
    expect(
      () => viewModel.state.layers.add(oldState.layers.first),
      throwsUnsupportedError,
    );
    viewModel.dispose();
  });

  test('invalid and unchanged commands do not save or notify', () async {
    final repository = FakeRhythmSettingsRepository();
    final viewModel = RhythmViewModel(repository: repository);
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    await viewModel.setTempo.execute(19);
    await viewModel.setTempo.execute(301);
    await viewModel.setTempo.execute(120);
    await viewModel.setLayerEnabled.execute(
      const RhythmLayerEnabledCommand(-1, true),
    );
    await viewModel.setLayerEnabled.execute(
      const RhythmLayerEnabledCommand(4, true),
    );
    await viewModel.setLayerEnabled.execute(
      const RhythmLayerEnabledCommand(0, false),
    );
    await viewModel.setLayerBeats.execute(const RhythmLayerBeatsCommand(0, 0));
    await viewModel.setLayerBeats.execute(const RhythmLayerBeatsCommand(0, 17));
    await viewModel.setLayerBeats.execute(const RhythmLayerBeatsCommand(4, 3));
    await viewModel.setLayerBeats.execute(const RhythmLayerBeatsCommand(0, 4));

    expect(repository.saveCount, 0);
    expect(notifications, 0);
    viewModel.dispose();
  });
}
