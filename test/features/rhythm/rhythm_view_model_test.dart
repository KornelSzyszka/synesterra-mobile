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

  test('commands persist immutable state and notify listeners', () {
    final repository = FakeRhythmSettingsRepository();
    final viewModel = RhythmViewModel(repository: repository);
    final oldState = viewModel.state;
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    viewModel.setTempo(300);
    viewModel.setLayerEnabled(1, true);
    viewModel.setLayerBeats(1, 16);

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

  test('invalid and unchanged commands do not save or notify', () {
    final repository = FakeRhythmSettingsRepository();
    final viewModel = RhythmViewModel(repository: repository);
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    viewModel.setTempo(19);
    viewModel.setTempo(301);
    viewModel.setTempo(120);
    viewModel.setLayerEnabled(-1, true);
    viewModel.setLayerEnabled(4, true);
    viewModel.setLayerEnabled(0, false);
    viewModel.setLayerBeats(0, 0);
    viewModel.setLayerBeats(0, 17);
    viewModel.setLayerBeats(4, 3);
    viewModel.setLayerBeats(0, 4);

    expect(repository.saveCount, 0);
    expect(notifications, 0);
    viewModel.dispose();
  });
}
