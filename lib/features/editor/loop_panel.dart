import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/loop.dart';
import '../../shared/instrument_mist/instrument_mist.dart';
import '../../shared/loop_view/loop_view.dart';
import '../../shared/loop_view/loop_view_state.dart';
import '../../shared/loop_view/position_source.dart';
import '../../shared/theme/ambient_scope.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/ground_palette.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';
import '../../shared/widgets/round_components.dart';
import 'editor_style.dart';
import 'loop_edits.dart' show stepMark, maxLoopCycleBeats;
import 'loop_editor_view_model.dart';
import 'step_grid.dart';
import 'test_sound.dart';

/// Build a loop from 2-4 layers, hear it, see it and save it. Play/Stop and
/// the tempo stay visible at the bottom, on a glass bar over the mist.
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
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.lg,
                Space.lg,
                Space.xl,
              ),
              children: [
                _header(context),
                const SizedBox(height: Space.md),
                _dice(context),
                const SizedBox(height: Space.lg),
                LoopView(
                  key: const Key('loop-view'),
                  state: LoopViewState.fromDocument(_vm.document),
                  source: widget.position,
                  initialMode:
                      _vm.document.presentation.visualMode == 'timeline'
                      ? LoopViewMode.timeline
                      : LoopViewMode.circle,
                ),
                const SizedBox(height: Space.xl),
                _cycle(context),
                for (var i = 0; i < _vm.layerCount; i++) ...[
                  const SizedBox(height: Space.lg),
                  _LayerCard(viewModel: _vm, index: i),
                ],
                const SizedBox(height: Space.lg),
                Center(
                  child: _vm.canAddLayer
                      ? TactileChip(
                          key: const Key('loop-add-layer'),
                          label: 'Add a layer',
                          onPressed: _vm.addLayer,
                        )
                      : Text(
                          'A loop has at most 4 layers.',
                          style: roundText(
                            context,
                            color: groundOf(context).muted,
                          ),
                        ),
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
    final palette = groundOf(context);
    final saveError = _vm.saveError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('loop-name'),
          controller: _name,
          maxLength: 40,
          style: roundText(
            context,
            color: palette.text,
            size: TypeScale.title,
            serif: true,
          ),
          decoration: InputDecoration(
            labelText: 'Loop name',
            errorText: _vm.nameValid ? null : 'Give the loop a name',
          ),
          onChanged: _vm.setName,
        ),
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: Space.sm),
                child: Text(
                  _vm.persisted
                      ? (_vm.dirty ? 'Changed, not saved yet' : 'Saved')
                      : 'Not in your library yet',
                  style: roundText(
                    context,
                    color: palette.muted,
                    size: TypeScale.caption,
                  ),
                ),
              ),
            ),
            TactileChip(
              key: const Key('loop-open'),
              label: 'Open',
              onPressed: _openOther,
            ),
            const SizedBox(width: Space.sm),
            Opacity(
              // Off until there is something to save; gold when there is.
              opacity: _vm.canSave ? 1 : .5,
              child: TactileChip(
                key: const Key('loop-save'),
                label: 'Save',
                primary: _vm.canSave,
                onPressed: _vm.canSave ? _save : null,
              ),
            ),
          ],
        ),
        if (saveError != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm, left: Space.sm),
            child: Text(
              saveError,
              style: roundText(
                context,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  /// The dice: a new random loop replaces this one as an unsaved change
  /// (never played by itself); undo brings back the loop before the last
  /// roll.
  Widget _dice(BuildContext context) => Row(
    children: [
      RoundIconButton(
        key: const Key('loop-randomize'),
        icon: Icons.casino_outlined,
        label: 'Randomize loop',
        onPressed: _vm.randomize,
      ),
      const SizedBox(width: Space.sm),
      Expanded(
        child: Text(
          'Roll a new loop. Nothing is kept until you save.',
          style: roundText(
            context,
            color: groundOf(context).muted,
            size: TypeScale.caption,
          ),
        ),
      ),
      if (_vm.canUndoRandomize)
        RoundIconButton(
          key: const Key('loop-randomize-undo'),
          icon: Icons.undo_rounded,
          label: 'Undo randomize',
          onPressed: _vm.undoRandomize,
        ),
    ],
  );

  Widget _cycle(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SoftHeader('Cycle'),
              const SizedBox(height: Space.sm),
              Text(
                'How many beats the loop lasts before it repeats.',
                style: roundText(
                  context,
                  color: groundOf(context).muted,
                  size: TypeScale.caption,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: Space.md),
        TrayStepper(
          key: const Key('loop-cycle'),
          value: _vm.cycleBeats,
          min: 1,
          max: maxLoopCycleBeats,
          label: 'beats',
          color: tokens.text,
          onChanged: _vm.setCycleBeats,
        ),
      ],
    );
  }
}

/// Asks before the loop being edited is replaced; the safe answer is Cancel.
Future<bool> confirmDiscardLoop(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => roundDialog(
        context,
        AlertDialog(
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
      ),
    ) ??
    false;

/// One layer as an organic card with a faint halo of the layer's colour.
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
    final scope = AmbientScope.maybeOf(context);
    final palette = GroundPalette.of(tokens, GroundTone.dark, color);
    final surfaces = Surfaces(palette);
    final muted = surfaces.mutedOn(SurfaceStyle.organic);
    return AmbientScope(
      palette: palette,
      drift: scope?.drift,
      tapStrength: scope?.tapStrength,
      gate: scope?.gate,
      child: Builder(
        builder: (context) => RoundSurface(
          key: Key('layer-$index'),
          style: SurfaceStyle.organic,
          shape: PebbleShape(seed: index + 2, exponent: 4.6),
          padding: const EdgeInsets.fromLTRB(
            Space.xl,
            Space.xl,
            Space.xl - 2,
            Space.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  NumberBadge(number: number, color: color),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      'Layer $number',
                      style: roundText(
                        context,
                        color: surfaces.textOn(SurfaceStyle.organic),
                        size: TypeScale.bodyLarge,
                        serif: true,
                      ),
                    ),
                  ),
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
                    RoundIconButton(
                      key: Key('layer-remove-$index'),
                      icon: Icons.close_rounded,
                      label: 'Remove layer $number',
                      size: 38,
                      onPressed: () => vm.removeLayer(index),
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
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
                  TactileCapsule(
                    key: Key('layer-note-$index'),
                    semanticsLabel: 'Note ${noteLabel(layer.pitch)}',
                    onPressed: () async {
                      final pitch = await showDialog<int>(
                        context: context,
                        builder: (_) => _NoteDialog(initial: layer.pitch),
                      );
                      if (pitch != null) vm.setLayerPitch(index, pitch);
                    },
                    child: SizedBox(
                      width: 34,
                      child: Text(
                        noteLabel(layer.pitch),
                        textAlign: TextAlign.center,
                        style: roundText(
                          context,
                          color: surfaces.textOn(SurfaceStyle.tactile),
                          size: TypeScale.bodyLarge,
                          serif: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Hits per cycle',
                      style: roundText(
                        context,
                        color: surfaces.textOn(SurfaceStyle.organic),
                      ),
                    ),
                  ),
                  TrayStepper(
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
              const SizedBox(height: Space.sm),
              Text(
                'Tap a hit to make it strong, tap again to leave it out.',
                style: roundText(
                  context,
                  color: muted,
                  size: TypeScale.caption,
                ),
              ),
              const SizedBox(height: Space.sm),
              StepGrid(
                layerIndex: index,
                layerLabel: 'Layer $number',
                marks: [for (final step in layer.pattern.steps) stepMark(step)],
                color: color,
                onToggle: (step) => vm.toggleStep(index, step),
              ),
              const SizedBox(height: Space.md),
              RoundSlider(
                key: Key('layer-volume-$index'),
                label: 'Volume',
                value: layer.mix.gain.toDouble(),
                onChanged: (value) => vm.setLayerVolume(index, value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `A4` for MIDI 69.
String noteLabel(int midi) => TestNote(midi).label;

/// The instrument's mist in a small glass vessel.
class _Vessel extends StatelessWidget {
  const _Vessel({required this.instrument, this.size = 36});

  /// Null when the instrument is missing.
  final Instrument? instrument;
  final double size;

  @override
  Widget build(BuildContext context) {
    final instrument = this.instrument;
    return SizedBox.square(
      dimension: size,
      child: RoundSurface(
        style: SurfaceStyle.glass,
        shape: RoundShape.circle,
        child: Center(
          child: instrument != null
              ? InstrumentMist(instrument: instrument, size: size - 6)
              : Icon(
                  Icons.music_off_outlined,
                  size: size * .5,
                  color: Theme.of(context).colorScheme.error,
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
    final name = instrument?.name ?? 'missing sound';
    return TactileCapsule(
      semanticsLabel: 'Layer $number sound: $name. Change',
      onPressed: onPressed,
      padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.lg, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Vessel(instrument: instrument),
          const SizedBox(width: Space.sm),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: roundText(
                context,
                color: instrument == null
                    ? Theme.of(context).colorScheme.error
                    : textOn(context, SurfaceStyle.tactile),
                weight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The list rows of a sheet: capsule ink, the sheet's text colours.
ListTile _sheetTile(
  BuildContext context, {
  required Key key,
  required Widget title,
  Widget? leading,
  String? subtitle,
  Widget? trailing,
  required VoidCallback onTap,
}) => ListTile(
  key: key,
  shape: const StadiumBorder(),
  leading: leading,
  title: title,
  subtitle: subtitle == null
      ? null
      : Text(
          subtitle,
          style: roundText(
            context,
            color: mutedTextOn(context, SurfaceStyle.glass),
            size: TypeScale.caption,
          ),
        ),
  trailing: trailing,
  onTap: onTap,
);

class _SoundSheet extends StatelessWidget {
  const _SoundSheet({required this.instruments, required this.selected});

  final List<Instrument> instruments;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final palette = groundOf(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.xxl,
            Space.lg,
            Space.lg,
          ),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Space.sm),
              child: SoftHeader('Choose a sound'),
            ),
            const SizedBox(height: Space.md),
            for (final instrument in instruments)
              _sheetTile(
                context,
                key: Key('pick-sound-${instrument.id}'),
                leading: _Vessel(instrument: instrument, size: 44),
                title: Text(instrument.name),
                subtitle: instrument.tags.isEmpty
                    ? null
                    : instrument.tags.join(' · '),
                trailing: instrument.id == selected
                    ? Icon(Icons.check_rounded, color: palette.accent)
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
    return roundDialog(
      context,
      AlertDialog(
        title: Text('Note ${noteLabel(_midi)}', key: const Key('note-preview')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (var i = 0; i < _names.length; i++)
                  TactileChip(
                    key: Key('note-name-$i'),
                    label: _names[i],
                    selected: i == _midi % 12,
                    onPressed: () => _set(name: i),
                  ),
              ],
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                const Expanded(child: Text('Octave')),
                TrayStepper(
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
      ),
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
    final mine = viewModel.savedLoops;
    Widget tile(Loop loop, bool existing, String key) => _sheetTile(
      context,
      key: Key(key),
      title: Text(loop.name),
      subtitle: '${loop.hitsPerLayer.join(':')} · ${loop.layerCount} layers',
      onTap: () => Navigator.pop(context, (loop, existing)),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.xxl,
            Space.lg,
            Space.lg,
          ),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Space.sm),
              child: SoftHeader('My loops'),
            ),
            if (mine.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: Space.md,
                ),
                child: Text(
                  'No saved loops yet.',
                  style: roundText(
                    context,
                    color: mutedTextOn(context, SurfaceStyle.glass),
                  ),
                ),
              ),
            for (final loop in mine) tile(loop, true, 'open-mine-${loop.id}'),
            const SizedBox(height: Space.lg),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Space.sm),
              child: SoftHeader('Start from a factory loop'),
            ),
            const SizedBox(height: Space.sm),
            for (final loop in factoryLoops)
              tile(loop, false, 'open-factory-${loop.id}'),
          ],
        ),
      ),
    );
  }
}

/// Play/Stop and the tempo on a glass capsule that floats over the mist, with
/// a plain note above it when something is wrong or still loading.
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.xs,
          Space.lg,
          Space.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Text(
                  note,
                  key: const Key('loop-transport-note'),
                  textAlign: TextAlign.center,
                  style: roundText(
                    context,
                    color: vm.playbackProblem != null
                        ? Theme.of(context).colorScheme.error
                        : groundOf(context).muted,
                    size: TypeScale.caption,
                  ),
                ),
              ),
            GlassPanel(
              key: const Key('loop-transport'),
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.sm,
                Space.md + 2,
                Space.sm,
              ),
              child: Row(
                children: [
                  PlayDisc(
                    key: const Key('loop-play'),
                    playing: vm.playing,
                    onPressed: vm.togglePlay,
                  ),
                  const Spacer(),
                  TrayStepper(
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
            ),
          ],
        ),
      ),
    );
  }
}
