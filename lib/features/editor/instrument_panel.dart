import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../shared/instrument_figure/instrument_sound_view.dart';
import '../../shared/instrument_mist/mist_spec.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';
import 'envelope_editor.dart';
import 'eq_editor.dart';
import 'instrument_editor_view_model.dart';
import 'spectrum_editor.dart';
import 'test_sound.dart';
import '../../shared/theme/design_scale.dart';

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

  Future<void> _startFrom(Instrument preset) async {
    final vm = widget.viewModel;
    if (vm.dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text('Starting from a preset replaces this draft.'),
          actions: [
            TextButton(
              key: const Key('start-from-cancel'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              key: const Key('start-from-discard'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    vm.startFrom(preset);
    vm.audition();
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
                padding: const EdgeInsets.all(Space.lg),
                children: [
                  _StartFrom(onPick: _startFrom),
                  const SizedBox(height: Space.md),
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
                        const SizedBox(height: Space.lg),
                        Center(
                          child: InstrumentSoundView(
                            key: const Key('instrument-preview'),
                            instrument: instrument,
                            testHz: vm.testHz,
                            size: 220,
                            onTap: vm.audition,
                            pulseToken: vm.auditionCount,
                          ),
                        ),
                        const SizedBox(height: Space.sm),
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
                        const SizedBox(height: Space.sm),
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
                              fontSize: TypeScale.caption,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  _TestSoundPanel(viewModel: vm),
                  const SizedBox(height: Space.lg),
                  DesignPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('Spectrum'),
                        const SizedBox(height: Space.sm),
                        SpectrumEditor(
                          amplitudes: instrument.harmonics,
                          shaped: shapedHarmonics(
                            instrument,
                            fundamentalHz: vm.testHz,
                          ),
                          selected: vm.selectedHarmonic,
                          color: tokens
                              .layerColors[identityColorIndex(instrument.id)],
                          onChange: (changes, select) =>
                              vm.setHarmonics(changes, select: select),
                          onChangeEnd: vm.auditionSoon,
                        ),
                        const SizedBox(height: Space.xs),
                        _ValueSlider(
                          key: const Key('spectrum-selected'),
                          label: 'Harmonic ${vm.selectedHarmonic + 1}',
                          valueText:
                              '${(instrument.harmonics[vm.selectedHarmonic] * 100).round()}%',
                          value: instrument.harmonics[vm.selectedHarmonic],
                          onChanged: (value) =>
                              vm.setHarmonic(vm.selectedHarmonic, value),
                          onChangeEnd: vm.auditionSoon,
                        ),
                        const SizedBox(height: Space.xs),
                        Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('Shape'),
                            for (final shape in SpectrumShape.values)
                              ActionChip(
                                key: Key('spectrum-shape-${shape.name}'),
                                label: Text(shape.label),
                                onPressed: () {
                                  vm.applySpectrumShape(shape);
                                  vm.auditionSoon();
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          'Drag across the bars to draw them. White marks show '
                          'each harmonic after the EQ. Shapes and Brightness '
                          'redraw every bar.',
                          style: TextStyle(
                            color: tokens.muted,
                            fontSize: TypeScale.caption,
                          ),
                        ),
                        const SizedBox(height: Space.sm),
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
                  const SizedBox(height: Space.lg),
                  DesignPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('Envelope'),
                        const SizedBox(height: Space.sm),
                        EnvelopeEditor(
                          attackMs: instrument.attackMs,
                          decayMs: instrument.decayMs,
                          color: tokens
                              .layerColors[identityColorIndex(instrument.id)],
                          onChange: vm.setEnvelope,
                          onChangeEnd: vm.auditionSoon,
                        ),
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
                  const SizedBox(height: Space.lg),
                  DesignPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('EQ'),
                        const SizedBox(height: Space.sm),
                        EqEditor(
                          eq: instrument.eq,
                          testHz: vm.testHz,
                          color: tokens
                              .layerColors[identityColorIndex(instrument.id)],
                          onChange: (eq) => vm.setEq(
                            lowDb: eq.lowDb,
                            midDb: eq.midDb,
                            highDb: eq.highDb,
                          ),
                          onChangeEnd: vm.auditionSoon,
                        ),
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
                  const SizedBox(height: Space.lg),
                  _TagsPanel(viewModel: vm),
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

// Decay feels even on a logarithmic scale.
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
      spacing: Space.sm,
      runSpacing: Space.xs,
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
          padding: const EdgeInsets.only(top: Space.sm),
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
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.sm,
            Space.lg,
            Space.sm,
          ),
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

/// Picks what is played to test the instrument. It is not part of the
/// instrument: it is not saved and never marks the instrument as changed.
class _TestSoundPanel extends StatelessWidget {
  const _TestSoundPanel({required this.viewModel});

  final InstrumentEditorViewModel viewModel;

  static const _names = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final sound = viewModel.testSound;
    final isChord = sound is TestChord;
    final pitchClass = sound.rootMidi % 12;
    final octave = sound.rootMidi ~/ 12 - 1;
    final quality = sound is TestChord ? sound.quality : ChordQuality.major;

    // Reads the current test sound when a control is used, not the one the
    // widget was built with, so quick successive changes build on each other.
    void choose({
      bool? chord,
      int? pitchClass,
      int? octave,
      ChordQuality? quality,
    }) {
      final current = viewModel.testSound;
      final midi =
          ((octave ?? current.rootMidi ~/ 12 - 1) + 1) * 12 +
          (pitchClass ?? current.rootMidi % 12);
      final newQuality =
          quality ??
          (current is TestChord ? current.quality : ChordQuality.major);
      viewModel.setTestSound(
        (chord ?? current is TestChord)
            ? TestChord(midi, newQuality)
            : TestNote(midi),
      );
    }

    return DesignPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Test sound'),
          const SizedBox(height: Space.xs),
          Text(
            'Only for hearing the instrument. It is not saved with it.',
            style: TextStyle(color: tokens.muted, fontSize: TypeScale.caption),
          ),
          const SizedBox(height: Space.md),
          SegmentedButton<bool>(
            key: const Key('test-mode'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, 48)),
            ),
            segments: const [
              ButtonSegment(value: false, label: Text('Note')),
              ButtonSegment(value: true, label: Text('Chord')),
            ],
            selected: {isChord},
            onSelectionChanged: (selection) => choose(chord: selection.single),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              for (var i = 0; i < _names.length; i++)
                ChoiceChip(
                  key: Key('test-root-$i'),
                  label: Text(_names[i]),
                  selected: i == pitchClass,
                  onSelected: (_) => choose(pitchClass: i),
                ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              const Expanded(child: Text('Octave')),
              NumberStepper(
                key: const Key('test-octave'),
                value: octave,
                min: 1,
                max: 7,
                label: 'octave',
                color: tokens.text,
                onChanged: (value) => choose(octave: value),
              ),
            ],
          ),
          if (isChord) ...[
            const SizedBox(height: Space.xs),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                for (final option in ChordQuality.values)
                  ChoiceChip(
                    key: Key('test-quality-${option.name}'),
                    label: Text(option.label),
                    selected: option == quality,
                    onSelected: (_) => choose(quality: option),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.sm),
          Text(
            'Plays ${sound.label}',
            key: const Key('test-label'),
            style: TextStyle(color: tokens.muted),
          ),
        ],
      ),
    );
  }
}

/// Tags are saved with the instrument and help find it in the library.
class _TagsPanel extends StatefulWidget {
  const _TagsPanel({required this.viewModel});

  final InstrumentEditorViewModel viewModel;

  @override
  State<_TagsPanel> createState() => _TagsPanelState();
}

class _TagsPanelState extends State<_TagsPanel> {
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add(String raw) {
    if (raw.trim().isEmpty) return;
    final vm = widget.viewModel;
    final normalized = Instrument.normalizeTag(raw);
    if (vm.addTag(raw)) {
      _input.clear();
      setState(() => _error = null);
    } else if (!vm.canAddTag) {
      setState(
        () =>
            _error = 'An instrument can have up to ${Instrument.maxTags} tags.',
      );
    } else if (normalized != null && vm.tags.contains(normalized)) {
      setState(() => _error = 'That tag is already there.');
    } else {
      setState(
        () => _error =
            'Use letters, digits, spaces or dashes, up to 24 characters.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final vm = widget.viewModel;
    final suggestions = [
      for (final tag in suggestedInstrumentTags)
        if (!vm.tags.contains(tag)) tag,
    ];
    return DesignPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Tags'),
          const SizedBox(height: Space.xs),
          Text(
            'Labels to find this instrument again in the library.',
            style: TextStyle(color: tokens.muted, fontSize: TypeScale.caption),
          ),
          const SizedBox(height: Space.sm),
          if (vm.tags.isEmpty)
            Text('No tags yet.', style: TextStyle(color: tokens.muted))
          else
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                for (final tag in vm.tags)
                  InputChip(
                    key: Key('tag-$tag'),
                    label: Text(tag),
                    deleteButtonTooltipMessage: 'Remove tag $tag',
                    onDeleted: () => vm.removeTag(tag),
                  ),
              ],
            ),
          if (vm.canAddTag) ...[
            const SizedBox(height: Space.sm),
            TextField(
              key: const Key('instrument-tag-input'),
              controller: _input,
              textInputAction: TextInputAction.done,
              onSubmitted: _add,
              decoration: InputDecoration(
                labelText: 'Add a tag',
                errorText: _error,
                suffixIcon: IconButton(
                  key: const Key('instrument-tag-add'),
                  tooltip: 'Add tag',
                  icon: const Icon(Icons.add),
                  onPressed: () => _add(_input.text),
                ),
              ),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  for (final tag in suggestions)
                    ActionChip(
                      key: Key('suggest-$tag'),
                      label: Text(tag),
                      onPressed: () => vm.addTag(tag),
                    ),
                ],
              ),
            ],
          ] else
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'That is the most tags an instrument can have.',
                style: TextStyle(
                  color: tokens.muted,
                  fontSize: TypeScale.caption,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
