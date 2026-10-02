import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../shared/formatting/note_name.dart';
import '../../shared/instrument_mist/instrument_mist.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';
import 'instrument_editor_view_model.dart';

/// Shape the sound of one instrument and see its mist react.
class InstrumentPanel extends StatefulWidget {
  const InstrumentPanel({super.key, required this.viewModel});

  final InstrumentEditorViewModel viewModel;

  @override
  State<InstrumentPanel> createState() => _InstrumentPanelState();
}

class _InstrumentPanelState extends State<InstrumentPanel> {
  late final TextEditingController _name = TextEditingController(
    text: widget.viewModel.name,
  );

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_syncName);
  }

  /// Keeps the field in step when the view model replaces the name (a preset
  /// was chosen). Typing already matches, so it is a no-op then.
  void _syncName() {
    if (_name.text != widget.viewModel.name) {
      _name.text = widget.viewModel.name;
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_syncName);
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final tokens = SynesterraTokens.of(context);
        final instrument = vm.instrument;
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _StartFrom(
                    onPick: (preset) {
                      vm.startFrom(preset);
                      vm.audition();
                    },
                  ),
                  const SizedBox(height: 12),
                  DesignPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          key: const Key('instrument-name'),
                          controller: _name,
                          onChanged: vm.setName,
                          maxLength: Instrument.maxNameLength,
                          buildCounter: (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                          decoration: InputDecoration(
                            labelText: 'Name',
                            errorText: vm.nameValid ? null : 'Give it a name',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: InstrumentMist(
                            key: const Key('instrument-mist'),
                            instrument: instrument,
                            size: 220,
                            interactive: true,
                            onTap: vm.audition,
                            pulseToken: vm.auditionCount,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: FilledButton.icon(
                            key: const Key('instrument-play'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(120, 48),
                            ),
                            onPressed: vm.audition,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Play'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<bool>(
                          valueListenable: vm.soundAvailable,
                          builder: (context, available, _) => Text(
                            available
                                ? 'Tap the mist or press Play to hear it. '
                                      'The sound updates when you let go of a '
                                      'control.'
                                : 'Sound is not available right now. The '
                                      'editor still works; try Play again.',
                            key: const Key('instrument-sound-note'),
                            style: TextStyle(
                              color: available
                                  ? tokens.muted
                                  : Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DesignPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('Sound'),
                        _ValueSlider(
                          key: const Key('instrument-pitch'),
                          label: 'Pitch',
                          valueText: pitchLabel(instrument.fundamentalHz),
                          value: _hzToSlider(instrument.fundamentalHz),
                          onChanged: (t) => vm.setPitchHz(_sliderToHz(t)),
                          onChangeEnd: vm.auditionSoon,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Expanded(child: Text('Harmonics')),
                            NumberStepper(
                              key: const Key('instrument-harmonics'),
                              value: vm.harmonicCount,
                              min: 1,
                              max: Instrument.maxHarmonics,
                              label: 'harmonics',
                              color: tokens.text,
                              repeatOnHold: true,
                              onChanged: (count) {
                                vm.setHarmonicCount(count);
                                vm.auditionSoon();
                              },
                            ),
                          ],
                        ),
                        _ValueSlider(
                          key: const Key('instrument-brightness'),
                          label: 'Brightness',
                          valueText: '${(vm.brightness * 100).round()}%',
                          value: vm.brightness,
                          onChanged: vm.setBrightness,
                          onChangeEnd: vm.auditionSoon,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DesignPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('Envelope'),
                        _ValueSlider(
                          key: const Key('instrument-attack'),
                          label: 'Attack',
                          valueText: '${instrument.attackMs} ms',
                          value: instrument.attackMs / Instrument.maxAttackMs,
                          onChanged: (t) => vm.setAttackMs(
                            (t * Instrument.maxAttackMs).round(),
                          ),
                          onChangeEnd: vm.auditionSoon,
                        ),
                        _ValueSlider(
                          key: const Key('instrument-decay'),
                          label: 'Decay',
                          valueText: '${instrument.decayMs} ms',
                          value: _msToSlider(instrument.decayMs),
                          onChanged: (t) => vm.setDecayMs(_sliderToMs(t)),
                          onChangeEnd: vm.auditionSoon,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DesignPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('EQ'),
                        _eqSlider(
                          'instrument-eq-low',
                          'Low · ${InstrumentEq.lowShelfHz.round()} Hz',
                          instrument.eq.lowDb,
                          (v) => vm.setEq(lowDb: v),
                        ),
                        _eqSlider(
                          'instrument-eq-mid',
                          'Mid · 1 kHz',
                          instrument.eq.midDb,
                          (v) => vm.setEq(midDb: v),
                        ),
                        _eqSlider(
                          'instrument-eq-high',
                          'High · 4 kHz',
                          instrument.eq.highDb,
                          (v) => vm.setEq(highDb: v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _SaveBar(viewModel: vm),
          ],
        );
      },
    );
  }

  Widget _eqSlider(
    String key,
    String label,
    double db,
    ValueChanged<double> onChanged,
  ) => _ValueSlider(
    key: Key(key),
    label: label,
    valueText: '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB',
    value: (db + InstrumentEq.maxGainDb) / (2 * InstrumentEq.maxGainDb),
    onChanged: (t) => onChanged((t * 2 - 1) * InstrumentEq.maxGainDb),
    onChangeEnd: widget.viewModel.auditionSoon,
  );
}

// Pitch and decay feel even on a logarithmic scale.
double _hzToSlider(double hz) =>
    math.log(hz / Instrument.minFundamentalHz) /
    math.log(Instrument.maxFundamentalHz / Instrument.minFundamentalHz);

double _sliderToHz(double t) =>
    Instrument.minFundamentalHz *
    math.pow(Instrument.maxFundamentalHz / Instrument.minFundamentalHz, t);

double _msToSlider(int ms) =>
    math.log(ms / Instrument.minDecayMs) /
    math.log(Instrument.maxDecayMs / Instrument.minDecayMs);

int _sliderToMs(double t) =>
    (Instrument.minDecayMs *
            math.pow(Instrument.maxDecayMs / Instrument.minDecayMs, t))
        .round();

class _StartFrom extends StatelessWidget {
  const _StartFrom({required this.onPick});

  final ValueChanged<Instrument> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Start from'),
        for (final preset in factoryInstruments)
          ActionChip(
            key: Key('start-from-${preset.id}'),
            label: Text(preset.name),
            onPressed: () => onPick(preset),
          ),
      ],
    );
  }
}

class _ValueSlider extends StatelessWidget {
  const _ValueSlider({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final String valueText;

  /// 0..1 position of the thumb.
  final double value;
  final ValueChanged<double> onChanged;

  /// Called when the user lets go of the thumb.
  final VoidCallback? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              Text(valueText, style: TextStyle(color: tokens.muted)),
            ],
          ),
        ),
        Semantics(
          label: '$label, $valueText',
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
            onChangeEnd: onChangeEnd == null ? null : (_) => onChangeEnd!(),
          ),
        ),
      ],
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.viewModel});

  final InstrumentEditorViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final status =
        viewModel.saveError ?? (viewModel.dirty ? 'Unsaved changes' : 'Saved');
    return Material(
      color: tokens.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  status,
                  key: const Key('instrument-status'),
                  style: TextStyle(
                    color: viewModel.saveError != null
                        ? Theme.of(context).colorScheme.error
                        : tokens.muted,
                  ),
                ),
              ),
              GoldPrimaryButton(
                key: const Key('instrument-save'),
                label: 'Save',
                onPressed: viewModel.canSave
                    ? () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final name = viewModel.name;
                        if (await viewModel.save()) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('Saved "$name"')),
                          );
                        }
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
