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
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/tap_glitch.dart';
import 'arrangement_panel_view_model.dart';

/// The Editor's Arrangement panel: chain loops from the library into
/// sections, play them in order, save the arrangement to the library.
///
/// Visual language v2: Play/Stop and Repeat all on a glass capsule, the
/// sections as organic cards, chips and round buttons for every action.
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
    final error = Theme.of(context).colorScheme.error;
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final model = _model;
        final palette = groundOf(context);
        final surfaces = Surfaces(palette);
        final playable = model.playableSections;
        final blocked = model.playBlockedReason;
        final note = model.playbackNote;
        return ListView(
          key: const Key('arrangement-panel'),
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.lg,
            Space.lg,
            Space.xl,
          ),
          children: [
            TextField(
              key: const Key('arrangement-name'),
              controller: _name,
              maxLength: Arrangement.maxNameLength,
              style: roundText(
                context,
                color: palette.text,
                size: TypeScale.title,
                serif: true,
              ),
              decoration: InputDecoration(
                labelText: 'Arrangement name',
                errorText: model.nameValid ? null : 'Enter a name.',
              ),
              onChanged: model.setName,
            ),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                TactileChip(
                  key: const Key('arrangement-new'),
                  label: 'New',
                  onPressed: _startNew,
                ),
                TactileChip(
                  key: const Key('arrangement-open'),
                  label: 'Open',
                  onPressed: _open,
                ),
                Opacity(
                  // Off until there is something to save; gold when there is.
                  opacity: model.canSave ? 1 : .5,
                  child: TactileChip(
                    key: const Key('arrangement-save'),
                    label: model.saving ? 'Saving…' : 'Save',
                    primary: model.canSave,
                    onPressed: model.canSave ? _save : null,
                  ),
                ),
              ],
            ),
            if (model.saveBlockedReason case final reason?)
              _Note(reason, color: palette.muted),
            if (model.saveError case final saveError?)
              _Note(saveError, color: error),
            const SizedBox(height: Space.lg),
            // Transport: Play/Stop and Repeat all on glass over the mist.
            GlassPanel(
              key: const Key('arrangement-transport'),
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.sm,
                Space.lg,
                Space.sm,
              ),
              child: Row(
                children: [
                  _Captioned(
                    key: const Key('arrangement-play'),
                    caption: model.isPlaying ? 'Stop' : 'Play',
                    child: RoundActionButton(
                      icon: model.isPlaying
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      label: model.isPlaying ? 'Stop' : 'Play',
                      size: 56,
                      onPressed: model.isPlaying
                          ? model.stop
                          : (model.canPlay ? model.play : null),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      blocked ??
                          'Plays at the tempo of the first loop: '
                              '${playable.first.document.transport.bpm.round()} BPM.',
                      key: blocked == null
                          ? null
                          : const Key('arrangement-play-reason'),
                      textAlign: TextAlign.center,
                      style: roundText(
                        context,
                        color: surfaces.mutedOn(SurfaceStyle.glass),
                        size: TypeScale.caption,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  _Captioned(
                    caption: 'Repeat all',
                    child: RoundIconButton(
                      key: const Key('arrangement-repeat-all'),
                      icon: Icons.repeat_rounded,
                      label: 'Repeat all',
                      selected: model.repeatAll,
                      onPressed: () => model.setRepeatAll(!model.repeatAll),
                    ),
                  ),
                ],
              ),
            ),
            if (note != null) _Note(note, color: error),
            if (model.sections.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              ArrangementStrip(
                sections: model.stripSections,
                source: widget.position,
              ),
            ],
            const SizedBox(height: Space.lg),
            _Header(
              'Sections ${model.sections.length} of ${Arrangement.maxSections}',
            ),
            const SizedBox(height: Space.md),
            for (var i = 0; i < model.sections.length; i++)
              _SectionCard(
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
            const SizedBox(height: Space.sm),
            Center(
              child: Opacity(
                opacity: model.canAddSection ? 1 : .5,
                child: TactileChip(
                  key: const Key('arrangement-add-section'),
                  label: 'Add a loop',
                  onPressed: model.canAddSection ? _addSection : null,
                ),
              ),
            ),
            if (!model.canAddSection)
              Center(
                child: _Note(
                  'An arrangement has at most ${Arrangement.maxSections} '
                  'sections.',
                  color: surfaces.mutedOn(SurfaceStyle.organic),
                ),
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
  const _Note(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.sm, 0),
    child: Text(
      text,
      style: roundText(context, color: color, size: TypeScale.caption),
    ),
  );
}

/// A round control with its word under it (for the eye; screen readers hear
/// the control's own label).
class _Captioned extends StatelessWidget {
  const _Captioned({super.key, required this.caption, required this.child});

  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      ExcludeSemantics(
        child: Text(
          caption,
          style: roundText(
            context,
            color: mutedTextOn(context, SurfaceStyle.glass),
            size: TypeScale.caption,
            weight: FontWeight.w500,
            spacing: .6,
          ),
        ),
      ),
    ],
  );
}

/// A quiet section header: a small gold light and a tracked-out label.
class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = groundOf(context);
    return Semantics(
      header: true,
      label: title,
      excludeSemantics: true,
      child: Row(
        children: [
          CustomPaint(
            size: const Size.square(12),
            painter: _MarkPainter(palette.accent),
          ),
          const SizedBox(width: Space.md),
          Text(
            title.toUpperCase(),
            style: roundText(
              context,
              color: palette.muted,
              size: TypeScale.caption,
              weight: FontWeight.w600,
              spacing: 2.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas
      ..drawCircle(
        c,
        size.shortestSide / 2,
        Paint()
          ..color = accent.withValues(alpha: .4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      )
      ..drawCircle(c, size.shortestSide / 4.5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.accent != accent;
}

/// One section as an organic card: its number, its loop (tap to pick
/// another), how often it repeats, and moving or removing it.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
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
    final surfaces = Surfaces(groundOf(context));
    final error = Theme.of(context).colorScheme.error;
    final number = index + 1;
    final loop = this.loop;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: RoundSurface(
        style: SurfaceStyle.organic,
        shape: PebbleShape(seed: index + 11, exponent: 4.6),
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          Space.md,
          Space.lg,
          Space.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _NumberOrb(number: number),
                const SizedBox(width: Space.md),
                Expanded(
                  child: _LoopButton(
                    key: Key('section-loop-$index'),
                    onTap: onChangeLoop,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          loop?.name ?? 'Missing loop',
                          style: roundText(
                            context,
                            color: loop == null
                                ? error
                                : surfaces.textOn(SurfaceStyle.organic),
                            size: TypeScale.bodyLarge,
                            serif: true,
                          ),
                        ),
                        Text(
                          loop == null
                              ? 'Skipped when playing. Pick another loop.'
                              : _loopSummary(loop),
                          style: roundText(
                            context,
                            color: surfaces.mutedOn(SurfaceStyle.organic),
                            size: TypeScale.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                RoundIconButton(
                  key: Key('section-remove-$index'),
                  icon: Icons.close_rounded,
                  label: 'Remove section $number',
                  size: 38,
                  onPressed: onRemove,
                ),
              ],
            ),
            Row(
              children: [
                KeyedSubtree(
                  key: Key('section-repeats-$index'),
                  child: RoundSurface(
                    style: SurfaceStyle.tray,
                    child: NumberStepper(
                      value: section.repeats,
                      min: ArrangementSection.minRepeats,
                      max: ArrangementSection.maxRepeats,
                      onChanged: onRepeats,
                      label: 'repeats',
                      color: tokens.text,
                    ),
                  ),
                ),
                const Spacer(),
                RoundIconButton(
                  key: Key('section-up-$index'),
                  icon: Icons.arrow_upward_rounded,
                  label: 'Move section $number earlier',
                  size: 38,
                  onPressed: onMoveUp,
                ),
                RoundIconButton(
                  key: Key('section-down-$index'),
                  icon: Icons.arrow_downward_rounded,
                  label: 'Move section $number later',
                  size: 38,
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

/// A section's number in a small gold-rimmed circle.
class _NumberOrb extends StatelessWidget {
  const _NumberOrb({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final palette = groundOf(context);
    final platform = Theme.of(context).platform;
    return SizedBox.square(
      dimension: 34,
      child: CustomPaint(
        painter: _OrbPainter(palette.accent),
        child: Center(
          child: Text(
            number.toString().padLeft(2, '0'),
            style: TextStyle(
              // Gold text fell below 4.5:1 on the lit card (Autumn).
              color: textOn(context, SurfaceStyle.organic),
              fontFamily: SynesterraFonts.monospace(platform),
              fontFamilyFallback: SynesterraFonts.monospaceFallback(platform),
              fontSize: TypeScale.caption,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas
      ..drawCircle(c, r, Paint()..color = accent.withValues(alpha: .08))
      ..drawCircle(
        c,
        r - .75,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accent.withValues(alpha: .5),
      );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.accent != accent;
}

/// The section's loop as a quiet button: tap to pick another loop. Answers
/// with the tap glitch in a capsule around the text.
class _LoopButton extends StatelessWidget {
  const _LoopButton({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    hint: 'Pick another loop',
    onTap: onTap,
    child: GestureDetector(
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: TapGlitch(
        shape: RoundShape.capsule,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class _LoopPicker extends StatelessWidget {
  const _LoopPicker({required this.title, required this.loops});

  final String title;
  final List<Loop> loops;

  @override
  Widget build(BuildContext context) {
    final palette = groundOf(context);
    final muted = mutedTextOn(context, SurfaceStyle.glass);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.lg),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.sm,
              Space.md,
              Space.md,
            ),
            child: Text(
              title,
              style: roundText(
                context,
                color: palette.text,
                size: TypeScale.title,
                serif: true,
              ),
            ),
          ),
          for (final loop in loops)
            ListTile(
              key: Key('loop-option-${loop.id}'),
              shape: const StadiumBorder(),
              leading: Icon(
                isFactoryId(loop.id)
                    ? Icons.auto_awesome_outlined
                    : Icons.loop_rounded,
                color: muted,
              ),
              title: Text(loop.name),
              subtitle: Text(
                '${isFactoryId(loop.id) ? 'Built in · ' : ''}'
                '${_loopSummary(loop)}',
                style: roundText(
                  context,
                  color: muted,
                  size: TypeScale.caption,
                ),
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
