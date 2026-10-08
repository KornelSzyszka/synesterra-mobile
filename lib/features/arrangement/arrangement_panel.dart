import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/arrangement_library_repository.dart';
import '../../data/repositories/library_item.dart';
import '../../data/repositories/loop.dart';
import '../../data/repositories/loop_library_repository.dart';
import '../../data/repositories/playback_repository.dart';
import '../../shared/loop_view/arrangement_strip.dart';
import '../../shared/loop_view/position_source.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';
import 'arrangement_panel_view_model.dart';

/// The Editor's Arrangement panel: chain loops from the library into
/// sections, play them in order, save the arrangement to the library.
///
/// It is the body of a tab: it has no app bar and expects a [Scaffold]
/// above it (for snack bars).
class ArrangementPanel extends StatefulWidget {
  const ArrangementPanel({
    super.key,
    required this.loops,
    required this.arrangements,
    required this.playback,
    required this.position,
    this.initial,
    this.onSaved,
    this.onModel,
  });

  final LoopLibraryRepository loops;
  final ArrangementLibraryRepository arrangements;
  final PlaybackRepository playback;

  /// The transport position of [playback] (the Editor shares one adapter
  /// between its panels). It only feeds the strip; it never drives transport.
  final PositionSource position;

  /// An arrangement opened from the library; null starts a new one.
  final Arrangement? initial;

  /// Called after every successful save with what was stored.
  final ValueChanged<Arrangement>? onSaved;

  /// Called with the panel's view model once it exists and with null when
  /// the panel goes away, so the host can protect unsaved work on exit.
  final ValueChanged<ArrangementPanelViewModel?>? onModel;

  @override
  State<ArrangementPanel> createState() => _ArrangementPanelState();
}

class _ArrangementPanelState extends State<ArrangementPanel> {
  late final ArrangementPanelViewModel _model = ArrangementPanelViewModel(
    loops: widget.loops,
    arrangements: widget.arrangements,
    playback: widget.playback,
    initial: widget.initial,
  );
  late final TextEditingController _name = TextEditingController(
    text: _model.name,
  );

  @override
  void initState() {
    super.initState();
    _model.addListener(_syncName);
    widget.onModel?.call(_model);
  }

  /// Opening another arrangement replaces the name field's text.
  void _syncName() {
    if (_name.text != _model.name) _name.text = _model.name;
  }

  @override
  void dispose() {
    widget.onModel?.call(null);
    _model.removeListener(_syncName);
    _model.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<String?> _pickLoop(String title) => showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => _LoopPicker(title: title, loops: _model.loopChoices),
  );

  Future<void> _addSection() async {
    final id = await _pickLoop('Add a loop');
    if (id != null && mounted) _model.addSection(id);
  }

  Future<void> _changeLoop(int index) async {
    final id = await _pickLoop('Section ${index + 1}: pick a loop');
    if (id != null && mounted) _model.replaceLoop(index, id);
  }

  /// With unsaved changes, asks before they are replaced. The safe answer is
  /// Cancel.
  Future<bool> _mayDiscard() async {
    if (!_model.hasUnsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('This arrangement has changes that are not saved.'),
        actions: [
          TextButton(
            key: const Key('arrangement-discard-cancel'),
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('arrangement-discard-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _open() async {
    final chosen = await showDialog<Arrangement>(
      context: context,
      builder: (context) =>
          _OpenDialog(items: widget.arrangements.snapshot.value.items),
    );
    if (chosen == null || !mounted) return;
    if (await _mayDiscard()) _model.open(chosen);
  }

  Future<void> _startNew() async {
    if (await _mayDiscard()) _model.startNew();
  }

  Future<void> _save() async {
    final saved = await _model.save();
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved.')));
    widget.onSaved?.call(saved);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final error = Theme.of(context).colorScheme.error;
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final model = _model;
        final playable = model.playableSections;
        final blocked = model.playBlockedReason;
        final note = model.playbackNote;
        return ListView(
          key: const Key('arrangement-panel'),
          padding: const EdgeInsets.all(Space.lg),
          children: [
            TextField(
              key: const Key('arrangement-name'),
              controller: _name,
              maxLength: Arrangement.maxNameLength,
              decoration: InputDecoration(
                labelText: 'Arrangement name',
                errorText: model.nameValid ? null : 'Enter a name.',
              ),
              onChanged: model.setName,
            ),
            Wrap(
              spacing: Space.sm,
              children: [
                TextButton.icon(
                  key: const Key('arrangement-new'),
                  onPressed: _startNew,
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('New'),
                ),
                TextButton.icon(
                  key: const Key('arrangement-open'),
                  onPressed: _open,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Open'),
                ),
                OutlinedButton.icon(
                  key: const Key('arrangement-save'),
                  onPressed: model.canSave ? _save : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(model.saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
            if (model.saveBlockedReason case final reason?)
              _Note(reason, color: tokens.muted),
            if (model.saveError case final saveError?)
              _Note(saveError, color: error),
            const SizedBox(height: Space.lg),
            DesignPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      KeyedSubtree(
                        key: const Key('arrangement-play'),
                        child: GoldPrimaryButton(
                          label: model.isPlaying ? 'Stop' : 'Play',
                          onPressed: model.isPlaying
                              ? model.stop
                              : (model.canPlay ? model.play : null),
                        ),
                      ),
                      const Spacer(),
                      Text('Repeat all', style: TextStyle(color: tokens.text)),
                      Switch(
                        key: const Key('arrangement-repeat-all'),
                        value: model.repeatAll,
                        onChanged: model.setRepeatAll,
                      ),
                    ],
                  ),
                  if (blocked != null)
                    _Note(
                      blocked,
                      key: const Key('arrangement-play-reason'),
                      color: tokens.muted,
                    )
                  else
                    _Note(
                      'Plays at the tempo of the first loop: '
                      '${playable.first.document.transport.bpm.round()} BPM.',
                      color: tokens.muted,
                    ),
                  if (note != null) _Note(note, color: error),
                  if (model.sections.isNotEmpty) ...[
                    const SizedBox(height: Space.md),
                    ArrangementStrip(
                      sections: model.stripSections,
                      source: widget.position,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
            SectionLabel(
              'Sections ${model.sections.length} of ${Arrangement.maxSections}',
            ),
            const SizedBox(height: Space.sm),
            for (var i = 0; i < model.sections.length; i++)
              _SectionRow(
                key: Key('section-$i'),
                index: i,
                count: model.sections.length,
                section: model.sections[i],
                loop: model.loopAt(i),
                onChangeLoop: () => _changeLoop(i),
                onRepeats: (value) => model.setRepeats(i, value),
                onMoveUp: i > 0 ? () => model.moveSection(i, i - 1) : null,
                onMoveDown: i < model.sections.length - 1
                    ? () => model.moveSection(i, i + 1)
                    : null,
                onRemove: () => model.removeSection(i),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('arrangement-add-section'),
                onPressed: model.canAddSection ? _addSection : null,
                icon: const Icon(Icons.add),
                label: const Text('Add a loop'),
              ),
            ),
            if (!model.canAddSection)
              _Note(
                'An arrangement has at most ${Arrangement.maxSections} '
                'sections.',
                color: tokens.muted,
              ),
          ],
        );
      },
    );
  }
}

/// `3:2 · 2 beats · 90 BPM`.
String _loopSummary(Loop loop) =>
    '${loop.hitsPerLayer.join(':')} · '
    '${loop.cycleBeats} ${loop.cycleBeats == 1 ? 'beat' : 'beats'} · '
    '${loop.bpm.round()} BPM';

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.sm),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: TypeScale.caption),
    ),
  );
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    super.key,
    required this.index,
    required this.count,
    required this.section,
    required this.loop,
    required this.onChangeLoop,
    required this.onRepeats,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final int index;
  final int count;
  final ArrangementSection section;

  /// Null when the section's loop is missing.
  final Loop? loop;
  final VoidCallback onChangeLoop;
  final ValueChanged<int> onRepeats;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final error = Theme.of(context).colorScheme.error;
    final number = index + 1;
    final loop = this.loop;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: DesignPanel(
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.sm,
          Space.xs,
          Space.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                LayerChip(number: number, color: tokens.muted),
                const SizedBox(width: Space.md),
                Expanded(
                  child: InkWell(
                    key: Key('section-loop-$index'),
                    onTap: onChangeLoop,
                    borderRadius: BorderRadius.circular(Radii.xs),
                    child: Semantics(
                      button: true,
                      hint: 'Pick another loop',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.xs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loop?.name ?? 'Missing loop',
                              style: TextStyle(
                                color: loop == null ? error : tokens.text,
                                fontSize: TypeScale.bodyLarge,
                              ),
                            ),
                            Text(
                              loop == null
                                  ? 'Skipped when playing. Pick another loop.'
                                  : _loopSummary(loop),
                              style: TextStyle(
                                color: tokens.muted,
                                fontSize: TypeScale.caption,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: Key('section-remove-$index'),
                  tooltip: 'Remove section $number',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRemove,
                ),
              ],
            ),
            Row(
              children: [
                KeyedSubtree(
                  key: Key('section-repeats-$index'),
                  child: NumberStepper(
                    value: section.repeats,
                    min: ArrangementSection.minRepeats,
                    max: ArrangementSection.maxRepeats,
                    onChanged: onRepeats,
                    label: 'repeats',
                    color: tokens.text,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: Key('section-up-$index'),
                  tooltip: 'Move section $number earlier',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: onMoveUp,
                ),
                IconButton(
                  key: Key('section-down-$index'),
                  tooltip: 'Move section $number later',
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: onMoveDown,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LoopPicker extends StatelessWidget {
  const _LoopPicker({required this.title, required this.loops});

  final String title;
  final List<Loop> loops;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: Text(
              title,
              style: TextStyle(color: tokens.text, fontSize: TypeScale.title),
            ),
          ),
          for (final loop in loops)
            ListTile(
              key: Key('loop-option-${loop.id}'),
              leading: Icon(
                isFactoryId(loop.id) ? Icons.auto_awesome_outlined : Icons.loop,
                color: tokens.muted,
              ),
              title: Text(loop.name),
              subtitle: Text(
                '${isFactoryId(loop.id) ? 'Built in · ' : ''}'
                '${_loopSummary(loop)}',
              ),
              onTap: () => Navigator.pop(context, loop.id),
            ),
        ],
      ),
    );
  }
}

class _OpenDialog extends StatelessWidget {
  const _OpenDialog({required this.items});

  final List<Arrangement> items;

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: const Text('Open an arrangement'),
    children: [
      if (items.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Space.xl),
          child: Text('No saved arrangements yet.'),
        ),
      for (final arrangement in items)
        SimpleDialogOption(
          key: Key('arrangement-option-${arrangement.id}'),
          onPressed: () => Navigator.pop(context, arrangement),
          child: Text(arrangement.name),
        ),
    ],
  );
}
