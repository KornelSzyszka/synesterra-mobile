import 'package:flutter/material.dart';

import '../../data/repositories/library_item.dart';
import '../../data/repositories/loop.dart';
import '../../data/repositories/loop_library_repository.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/round_screen.dart';
import 'library_widgets.dart';

/// Opens a loop. [existing] is true for the user's own loops (edited in
/// place) and false for a factory loop (read-only, so it is edited as a copy).
typedef OpenLoop = void Function(Loop loop, bool existing);

/// `3:2 · 2 layers · 90 BPM`: hits per layer, layer count and tempo.
String loopSummary(Loop loop) =>
    '${loop.hitsPerLayer.join(':')} · ${loop.layerCount} layers · '
    '${formatBpm(loop.bpm)} BPM';

String formatBpm(num bpm) =>
    bpm == bpm.roundToDouble() ? '${bpm.round()}' : bpm.toStringAsFixed(1);

class LoopsTab extends StatelessWidget {
  const LoopsTab({super.key, required this.library, required this.onOpen});

  final LoopLibraryRepository library;
  final OpenLoop onOpen;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LibrarySnapshot<Loop>>(
      valueListenable: library.snapshot,
      builder: (context, snapshot, _) => ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          UnreadableNote(count: snapshot.unreadableCount),
          const RoundSectionHeader('My loops'),
          if (snapshot.items.isEmpty)
            const EmptyNote(
              'No loops of your own yet. Copy a factory loop to start one.',
            ),
          for (final loop in snapshot.items)
            _LoopCard(
              loop: loop,
              onTap: () => onOpen(loop, true),
              actions: [
                RoundIconButton(
                  key: Key('loop-rename-${loop.id}'),
                  label: 'Rename ${loop.name}',
                  icon: Icons.edit_outlined,
                  onPressed: () => _rename(context, loop),
                ),
                RoundIconButton(
                  key: Key('loop-delete-${loop.id}'),
                  label: 'Delete ${loop.name}',
                  icon: Icons.delete_outline,
                  onPressed: () => deleteWithUndo(
                    context,
                    name: loop.name,
                    delete: () => library.delete(loop.id),
                    restore: () => library.save(loop),
                  ),
                ),
              ],
            ),
          const SizedBox(height: Space.lg),
          const RoundSectionHeader('Factory'),
          for (final loop in factoryLoops)
            _LoopCard(
              loop: loop,
              onTap: () => onOpen(loop, false),
              actions: [
                RoundIconButton(
                  key: Key('loop-copy-${loop.id}'),
                  label: 'Copy ${loop.name} to My loops',
                  icon: Icons.copy_outlined,
                  onPressed: () => _copy(context, loop),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, Loop loop) async {
    final name = await showRenameDialog(
      context,
      title: 'Rename loop',
      initial: loop.name,
    );
    if (name != null) await library.save(loop.copyWith(name: name));
  }

  Future<void> _copy(BuildContext context, Loop loop) async {
    final messenger = ScaffoldMessenger.of(context);
    final copy = loop.copyAsNew();
    await library.save(copy);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Copied as "${copy.name}"')));
  }
}

class _LoopCard extends StatelessWidget {
  const _LoopCard({
    required this.loop,
    required this.onTap,
    required this.actions,
  });

  final Loop loop;
  final VoidCallback onTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LibraryCard(
      key: Key('loop-tile-${loop.id}'),
      leading: const CardBadge(icon: Icons.autorenew),
      seed: loop.id.hashCode & 0xff,
      motionId: loop.id,
      title: loop.name,
      lines: [CardLine(loopSummary(loop))],
      onTap: onTap,
      actions: actions,
    );
  }
}
