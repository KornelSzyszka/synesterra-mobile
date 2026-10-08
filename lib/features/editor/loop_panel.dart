import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/loop.dart';
import '../../shared/instrument_mist/instrument_mist.dart';
import '../../shared/loop_view/loop_view.dart';
import '../../shared/loop_view/loop_view_state.dart';
import '../../shared/loop_view/position_source.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';
import 'loop_edits.dart' show StepMark, stepMark, maxLoopCycleBeats;
import 'loop_editor_view_model.dart';
import 'test_sound.dart';

/// Build a loop from 2-4 layers, hear it, see it and save it. Play/Stop and
/// the tempo stay visible at the bottom.
class LoopPanel extends StatefulWidget {
  const LoopPanel({super.key, required this.viewModel, required this.position});

  final LoopEditorViewModel viewModel;

  /// Where the transport is; drives the picture only.
  final PositionSource position;

  @override
  State<LoopPanel> createState() => _LoopPanelState();
}

class _LoopPanelState extends State<LoopPanel> {
  late final TextEditingController _name = TextEditingController(
    text: widget.viewModel.name,
  );

  LoopEditorViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_syncName);
  }

  /// Keeps the field in step when another loop is opened.
  void _syncName() {
    if (_name.text != _vm.name) _name.text = _vm.name;
  }

  @override
  void dispose() {
    _vm.removeListener(_syncName);
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (await _vm.save()) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Saved "${_vm.name}"')));
    }
  }

  Future<void> _openOther() async {
    final choice = await showModalBottomSheet<(Loop, bool)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OpenSheet(viewModel: _vm),
    );
    if (choice == null || !mounted) return;
    if (_vm.dirty && !await confirmDiscardLoop(context)) return;
    _vm.open(choice.$1, existing: choice.$2);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => Column(
        children: [
          Expanded(
            child: ListView(
              key: const Key('loop-panel-list'),
              padding: const EdgeInsets.all(Space.lg),
              children: [
                _header(context),
                const SizedBox(height: Space.lg),
                DesignPanel(
                  child: LoopView(
                    key: const Key('loop-view'),
                    state: LoopViewState.fromDocument(_vm.document),
                    source: widget.position,
                    initialMode:
                        _vm.document.presentation.visualMode == 'timeline'
                        ? LoopViewMode.timeline
                        : LoopViewMode.circle,
                  ),
                ),
                const SizedBox(height: Space.lg),
                _cycle(context),
                for (var i = 0; i < _vm.layerCount; i++) ...[
                  const SizedBox(height: Space.md),
                  _LayerCard(viewModel: _vm, index: i),
                ],
                const SizedBox(height: Space.md),
                if (_vm.canAddLayer)
                  OutlinedButton.icon(
                    key: const Key('loop-add-layer'),
                    onPressed: _vm.addLayer,
                    icon: const Icon(Icons.add),
                    label: const Text('Add a layer'),
                  )
                else
                  Text(
                    'A loop has at most 4 layers.',
                    style: TextStyle(color: SynesterraTokens.of(context).muted),
                  ),
              ],
            ),
          ),
          _TransportBar(viewModel: _vm),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return DesignPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('loop-name'),
            controller: _name,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: 'Loop name',
              errorText: _vm.nameValid ? null : 'Give the loop a name',
            ),
            onChanged: _vm.setName,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _vm.persisted
                      ? (_vm.dirty ? 'Changed, not saved yet' : 'Saved')
                      : 'Not in your library yet',
                  style: TextStyle(color: tokens.muted),
                ),
              ),
              TextButton.icon(
                key: const Key('loop-open'),
                onPressed: _openOther,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open'),
              ),
              const SizedBox(width: Space.sm),
              GoldPrimaryButton(
                key: const Key('loop-save'),
                label: 'Save',
                onPressed: _vm.canSave ? _save : null,
              ),
            ],
          ),
          if (_vm.saveError != null)
            Text(
              _vm.saveError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }

  Widget _cycle(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return DesignPanel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Cycle'),
                const SizedBox(height: Space.xs),
                Text(
                  'How many beats the loop lasts before it repeats.',
                  style: TextStyle(
                    color: tokens.muted,
                    fontSize: TypeScale.caption,
                  ),
                ),
              ],
            ),
          ),
          NumberStepper(
            key: const Key('loop-cycle'),
            value: _vm.cycleBeats,
            min: 1,
            max: maxLoopCycleBeats,
            label: 'beats',
            color: tokens.text,
            onChanged: _vm.setCycleBeats,
          ),
        ],
      ),
    );
  }
}

/// Asks before the loop being edited is replaced; the safe answer is Cancel.
Future<bool> confirmDiscardLoop(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('The loop you are editing has changes.'),
        actions: [
          TextButton(
            key: const Key('discard-cancel'),
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('discard-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    ) ??
    false;

class _LayerCard extends StatelessWidget {
  const _LayerCard({required this.viewModel, required this.index});

  final LoopEditorViewModel viewModel;
  final int index;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final vm = viewModel;
    final layer = vm.layer(index);
    final color = tokens.layerColors[index % tokens.layerColors.length];
    final on = !layer.mix.muted;
    final instrument = vm.instrumentFor(layer.instrumentId);
    final number = index + 1;
    return DesignPanel(
      key: Key('layer-$index'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LayerChip(number: number, color: color),
              const SizedBox(width: Space.md),
              Expanded(child: Text('Layer $number')),
              Semantics(
                label: 'Layer $number ${on ? 'on' : 'off'}',
                child: LayerToggle(
                  key: Key('layer-on-$index'),
                  value: on,
                  color: color,
                  onChanged: (value) => vm.setLayerOn(index, value),
                ),
              ),
              if (vm.canRemoveLayer)
                IconButton(
                  key: Key('layer-remove-$index'),
                  tooltip: 'Remove layer $number',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => vm.removeLayer(index),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: _SoundButton(
                  key: Key('layer-sound-$index'),
                  instrument: instrument,
                  number: number,
                  onPressed: () async {
                    final id = await showModalBottomSheet<String>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => _SoundSheet(
                        instruments: vm.availableInstruments,
                        selected: layer.instrumentId,
                      ),
                    );
                    if (id != null) vm.setLayerInstrument(index, id);
                  },
                ),
              ),
              const SizedBox(width: Space.sm),
              OutlinedButton(
                key: Key('layer-note-$index'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(72, 48),
                ),
                onPressed: () async {
                  final pitch = await showDialog<int>(
                    context: context,
                    builder: (_) => _NoteDialog(initial: layer.pitch),
                  );
                  if (pitch != null) vm.setLayerPitch(index, pitch);
                },
                child: Text(
                  noteLabel(layer.pitch),
                  semanticsLabel: 'Note ${noteLabel(layer.pitch)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              const Expanded(child: Text('Hits per cycle')),
              NumberStepper(
                key: Key('layer-hits-$index'),
                value: layer.pattern.steps.length,
                min: 1,
                max: vm.maxSteps,
                label: 'hits',
                color: color,
                onChanged: (value) => vm.setLayerSteps(index, value),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Tap a hit to make it strong, tap again to leave it out.',
            style: TextStyle(color: tokens.muted, fontSize: TypeScale.caption),
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (var s = 0; s < layer.pattern.steps.length; s++)
                _StepCell(
                  key: Key('step-$index-$s'),
                  mark: stepMark(layer.pattern.steps[s]),
                  color: color,
                  label: 'Layer $number, hit ${s + 1}',
                  onTap: () => vm.toggleStep(index, s),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              const Text('Volume'),
              Expanded(
                child: Slider(
                  key: Key('layer-volume-$index'),
                  value: layer.mix.gain.toDouble(),
                  semanticFormatterCallback: (value) =>
                      '${(value * 100).round()} percent',
                  onChanged: (value) => vm.setLayerVolume(index, value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `A4` for MIDI 69.
String noteLabel(int midi) => TestNote(midi).label;

class _StepCell extends StatelessWidget {
  const _StepCell({
    super.key,
    required this.mark,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final StepMark mark;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final fill = switch (mark) {
      StepMark.off => Colors.transparent,
      StepMark.on => color.withValues(alpha: .45),
      StepMark.accent => color,
    };
    return Semantics(
      button: true,
      label: '$label: ${mark.label}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.xs),
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: fill,
                border: Border.all(
                  color: mark == StepMark.off ? tokens.border : color,
                  width: mark == StepMark.accent ? 3 : 1,
                ),
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoundButton extends StatelessWidget {
  const _SoundButton({
    super.key,
    required this.instrument,
    required this.number,
    required this.onPressed,
  });

  /// Null when the layer's instrument is missing.
  final Instrument? instrument;
  final int number;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final name = instrument?.name ?? 'missing sound';
    return Semantics(
      button: true,
      label: 'Layer $number sound: $name. Change',
      excludeSemantics: true,
      onTap: onPressed,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          alignment: Alignment.centerLeft,
        ),
        onPressed: onPressed,
        child: Row(
          children: [
            if (instrument != null)
              InstrumentMist(instrument: instrument!, size: 32)
            else
              Icon(Icons.music_off_outlined, color: tokens.muted),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: instrument == null
                      ? Theme.of(context).colorScheme.error
                      : tokens.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoundSheet extends StatelessWidget {
  const _SoundSheet({required this.instruments, required this.selected});

  final List<Instrument> instruments;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(Space.lg),
          children: [
            const SectionLabel('Choose a sound'),
            const SizedBox(height: Space.sm),
            for (final instrument in instruments)
              ListTile(
                key: Key('pick-sound-${instrument.id}'),
                leading: InstrumentMist(instrument: instrument, size: 40),
                title: Text(instrument.name),
                subtitle: instrument.tags.isEmpty
                    ? null
                    : Text(
                        instrument.tags.join(' · '),
                        style: TextStyle(color: tokens.muted),
                      ),
                trailing: instrument.id == selected
                    ? Icon(Icons.check, color: tokens.accent)
                    : null,
                onTap: () => Navigator.pop(context, instrument.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial});

  final int initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
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

  late int _midi = widget.initial;

  /// Octaves 1..7 with every name give exactly C1..B7.
  void _set({int? name, int? octave}) => setState(
    () => _midi = ((octave ?? _midi ~/ 12 - 1) + 1) * 12 + (name ?? _midi % 12),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return AlertDialog(
      title: Text('Note ${noteLabel(_midi)}', key: const Key('note-preview')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              for (var i = 0; i < _names.length; i++)
                ChoiceChip(
                  key: Key('note-name-$i'),
                  label: Text(_names[i]),
                  selected: i == _midi % 12,
                  onSelected: (_) => _set(name: i),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              const Expanded(child: Text('Octave')),
              NumberStepper(
                key: const Key('note-octave'),
                value: _midi ~/ 12 - 1,
                min: 1,
                max: 7,
                label: 'octave',
                color: tokens.text,
                onChanged: (octave) => _set(octave: octave),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('note-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('note-ok'),
          onPressed: () => Navigator.pop(context, _midi),
          child: const Text('Use this note'),
        ),
      ],
    );
  }
}

/// Lists the user's loops (opened in place) and the factory loops (opened as
/// a copy). Pops `(loop, existing)`.
class _OpenSheet extends StatelessWidget {
  const _OpenSheet({required this.viewModel});

  final LoopEditorViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final mine = viewModel.savedLoops;
    Widget tile(Loop loop, bool existing, String key) => ListTile(
      key: Key(key),
      title: Text(loop.name),
      subtitle: Text(
        '${loop.hitsPerLayer.join(':')} · ${loop.layerCount} layers',
        style: TextStyle(color: tokens.muted),
      ),
      onTap: () => Navigator.pop(context, (loop, existing)),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(Space.lg),
          children: [
            const SectionLabel('My loops'),
            if (mine.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Text(
                  'No saved loops yet.',
                  style: TextStyle(color: tokens.muted),
                ),
              ),
            for (final loop in mine) tile(loop, true, 'open-mine-${loop.id}'),
            const SizedBox(height: Space.md),
            const SectionLabel('Start from a factory loop'),
            for (final loop in factoryLoops)
              tile(loop, false, 'open-factory-${loop.id}'),
          ],
        ),
      ),
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.viewModel});

  final LoopEditorViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final vm = viewModel;
    final missing = [
      for (var i = 0; i < vm.layerCount; i++)
        if (vm.isMissing(i)) i + 1,
    ];
    final note =
        vm.playbackProblem ??
        (vm.preparing
            ? 'Getting the sounds ready…'
            : missing.isEmpty
            ? null
            : 'Layer ${missing.join(', ')}: missing sound, plays silence.');
    return Material(
      color: tokens.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tokens.border)),
          ),
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.sm,
            Space.lg,
            Space.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: Text(
                    note,
                    key: const Key('loop-transport-note'),
                    style: TextStyle(
                      color: vm.playbackProblem != null
                          ? Theme.of(context).colorScheme.error
                          : tokens.muted,
                      fontSize: TypeScale.caption,
                    ),
                  ),
                ),
              Row(
                children: [
                  GoldPrimaryButton(
                    key: const Key('loop-play'),
                    label: vm.playing ? 'Stop' : 'Play',
                    onPressed: vm.togglePlay,
                  ),
                  const Spacer(),
                  NumberStepper(
                    key: const Key('loop-tempo'),
                    value: vm.tempo,
                    min: 20,
                    max: 300,
                    label: 'BPM',
                    color: tokens.accent,
                    repeatOnHold: true,
                    onChanged: vm.setTempo,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
