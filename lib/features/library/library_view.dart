import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/arrangement_library_repository.dart';
import '../../data/repositories/instrument_library_repository.dart';
import '../../data/repositories/loop_library_repository.dart';
import '../../shared/instrument_radar/instrument_radar_thumbnail.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';
import '../../shared/theme/design_scale.dart';
import 'arrangements_tab.dart';
import 'loops_tab.dart';

export 'arrangements_tab.dart' show OpenArrangement;
export 'loops_tab.dart' show OpenLoop;

/// Opens an instrument in the editor. [existing] is true for the user's own
/// instruments (edited in place) and false for a factory preset (copied).
typedef OpenInstrument = void Function(Instrument instrument, bool existing);

/// Library with one tab per editor panel, in the same order.
class LibraryView extends StatelessWidget {
  const LibraryView({
    super.key,
    required this.instrumentLibrary,
    required this.loopLibrary,
    required this.arrangementLibrary,
    required this.onOpenInstrument,
    required this.onOpenLoop,
    required this.onOpenArrangement,
  });

  final InstrumentLibraryRepository instrumentLibrary;
  final LoopLibraryRepository loopLibrary;
  final ArrangementLibraryRepository arrangementLibrary;
  final OpenInstrument onOpenInstrument;
  final OpenLoop onOpenLoop;
  final OpenArrangement onOpenArrangement;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          bottom: const TabBar(
            tabs: [
              Tab(key: Key('library-tab-instruments'), text: 'Instruments'),
              Tab(key: Key('library-tab-loops'), text: 'Loops'),
              Tab(key: Key('library-tab-arrangements'), text: 'Arrangements'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _InstrumentsTab(
              library: instrumentLibrary,
              onOpen: onOpenInstrument,
            ),
            LoopsTab(library: loopLibrary, onOpen: onOpenLoop),
            ArrangementsTab(
              library: arrangementLibrary,
              loops: loopLibrary,
              onOpen: onOpenArrangement,
            ),
          ],
        ),
      ),
    );
  }
}

class _InstrumentsTab extends StatefulWidget {
  const _InstrumentsTab({required this.library, required this.onOpen});

  final InstrumentLibraryRepository library;
  final OpenInstrument onOpen;

  @override
  State<_InstrumentsTab> createState() => _InstrumentsTabState();
}

class _InstrumentsTabState extends State<_InstrumentsTab> {
  /// The tag the list is filtered by; null shows everything.
  String? _tag;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return ValueListenableBuilder<InstrumentLibrarySnapshot>(
      valueListenable: widget.library.snapshot,
      builder: (context, snapshot, _) {
        final tags = {
          for (final i in [...snapshot.instruments, ...factoryInstruments])
            ...i.tags,
        }.toList()..sort();
        // A filter nobody has any more (the last such instrument was deleted
        // or retagged) falls back to showing everything.
        final tag = tags.contains(_tag) ? _tag : null;
        bool matches(Instrument i) => tag == null || i.tags.contains(tag);
        final mine = snapshot.instruments.where(matches).toList();
        final presets = factoryInstruments.where(matches).toList();
        return ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            if (snapshot.unreadableCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Text(
                  key: const Key('unreadable-note'),
                  '${snapshot.unreadableCount} stored '
                  '${snapshot.unreadableCount == 1 ? 'file' : 'files'} could '
                  'not be read. They were left untouched.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (tags.isNotEmpty) ...[
              const SectionLabel('Filter by tag'),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  FilterChip(
                    key: const Key('filter-all'),
                    label: const Text('All'),
                    selected: tag == null,
                    onSelected: (_) => setState(() => _tag = null),
                  ),
                  for (final option in tags)
                    FilterChip(
                      key: Key('filter-$option'),
                      label: Text(option),
                      selected: option == tag,
                      onSelected: (_) => setState(() => _tag = option),
                    ),
                ],
              ),
              const SizedBox(height: Space.lg),
            ],
            const SectionLabel('My instruments'),
            const SizedBox(height: Space.sm),
            if (mine.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.md),
                child: Text(
                  tag == null
                      ? 'No instruments yet. Save one from the Editor.'
                      : 'None of your instruments has the tag "$tag".',
                  style: TextStyle(color: tokens.muted),
                ),
              ),
            for (final instrument in mine)
              _InstrumentTile(
                key: Key('own-${instrument.id}'),
                instrument: instrument,
                onTap: () => widget.onOpen(instrument, true),
                onDelete: () => _delete(context, instrument),
              ),
            if (presets.isNotEmpty) ...[
              const SizedBox(height: Space.lg),
              const SectionLabel('Factory'),
              const SizedBox(height: Space.sm),
              for (final preset in presets)
                _InstrumentTile(
                  key: Key('factory-tile-${preset.id}'),
                  instrument: preset,
                  onTap: () => widget.onOpen(preset, false),
                ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, Instrument instrument) async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.library.delete(instrument.id);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${instrument.name}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => widget.library.save(instrument),
          ),
        ),
      );
  }
}

class _InstrumentTile extends StatelessWidget {
  const _InstrumentTile({
    super.key,
    required this.instrument,
    required this.onTap,
    this.onDelete,
  });

  final Instrument instrument;
  final VoidCallback onTap;

  /// Null for factory instruments, which cannot be deleted.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Material(
        color: tokens.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.border),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.sm,
                Space.xs,
                Space.sm,
              ),
              child: Row(
                children: [
                  InstrumentRadarThumbnail(instrument: instrument, size: 56),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(instrument.name),
                        Text(
                          '${instrument.harmonics.length} harmonics · '
                          '${instrument.decayMs} ms',
                          style: TextStyle(
                            color: tokens.muted,
                            fontSize: TypeScale.caption,
                          ),
                        ),
                        if (instrument.tags.isNotEmpty)
                          Text(
                            key: Key('tags-${instrument.id}'),
                            instrument.tags.join(' · '),
                            style: TextStyle(
                              color: tokens.accent,
                              fontSize: TypeScale.caption,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      key: Key('delete-${instrument.id}'),
                      tooltip: 'Delete ${instrument.name}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: onDelete,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
