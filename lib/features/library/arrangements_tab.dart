import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/arrangement_library_repository.dart';
import '../../data/repositories/loop.dart';
import '../../data/repositories/loop_library_repository.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';
import 'library_widgets.dart';

typedef OpenArrangement = void Function(Arrangement arrangement);

/// `2 sections · 6 repeats`.
String arrangementSummary(Arrangement arrangement) {
  final sections = arrangement.sections.length;
  final repeats = arrangement.totalRepeats;
  return '$sections ${sections == 1 ? 'section' : 'sections'} · '
      '$repeats ${repeats == 1 ? 'repeat' : 'repeats'}';
}

class ArrangementsTab extends StatelessWidget {
  const ArrangementsTab({
    super.key,
    required this.library,
    required this.loops,
    required this.onOpen,
  });

  final ArrangementLibraryRepository library;

  /// Resolves section loop ids, so a missing loop can be marked.
  final LoopLibraryRepository loops;
  final OpenArrangement onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([library.snapshot, loops.snapshot]),
      builder: (context, _) {
        final snapshot = library.snapshot.value;
        final loopSnapshot = loops.snapshot.value;
        return ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            UnreadableNote(count: snapshot.unreadableCount),
            if (snapshot.items.isEmpty)
              const EmptyNote(
                'No arrangements yet. An arrangement plays loops one after '
                'another.',
              ),
            for (final arrangement in snapshot.items)
              _ArrangementCard(
                arrangement: arrangement,
                resolve: (id) => findLoop(loopSnapshot, id),
                onTap: () => onOpen(arrangement),
                onRename: () => _rename(context, arrangement),
                onDelete: () => deleteWithUndo(
                  context,
                  name: arrangement.name,
                  delete: () => library.delete(arrangement.id),
                  restore: () => library.save(arrangement),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _rename(BuildContext context, Arrangement arrangement) async {
    final name = await showRenameDialog(
      context,
      title: 'Rename arrangement',
      initial: arrangement.name,
    );
    if (name != null) await library.save(arrangement.renamed(name));
  }
}

class _ArrangementCard extends StatelessWidget {
  const _ArrangementCard({
    required this.arrangement,
    required this.resolve,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final Arrangement arrangement;
  final Loop? Function(String id) resolve;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final id = arrangement.id;
    final names = [
      for (final section in arrangement.sections)
        '${resolve(section.loopId)?.name ?? 'missing loop'} ×${section.repeats}',
    ];
    final missing = arrangement.sections
        .where((section) => resolve(section.loopId) == null)
        .length;
    return LibraryCard(
      key: Key('arrangement-tile-$id'),
      leading: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: tokens.accent.withValues(alpha: .5)),
        ),
        child: Icon(Icons.queue_music, color: tokens.accent),
      ),
      title: arrangement.name,
      lines: [
        CardLine(arrangementSummary(arrangement)),
        CardLine(names.join(' → ')),
        if (missing > 0)
          CardLine(
            '$missing missing ${missing == 1 ? 'loop' : 'loops'}',
            color: Theme.of(context).colorScheme.error,
          ),
      ],
      onTap: onTap,
      actions: [
        IconButton(
          key: Key('arrangement-rename-$id'),
          tooltip: 'Rename ${arrangement.name}',
          icon: const Icon(Icons.edit_outlined),
          onPressed: onRename,
        ),
        IconButton(
          key: Key('arrangement-delete-$id'),
          tooltip: 'Delete ${arrangement.name}',
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
      ],
    );
  }
}
