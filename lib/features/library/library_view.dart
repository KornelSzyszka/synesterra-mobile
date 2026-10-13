import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/arrangement_library_repository.dart';
import '../../data/repositories/instrument_library_repository.dart';
import '../../data/repositories/loop_library_repository.dart';
import '../../shared/instrument_radar/instrument_radar_thumbnail.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/round_screen.dart';
import 'arrangements_tab.dart';
import 'library_tabs.dart';
import 'library_widgets.dart';
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
      child: RoundScreen(
        title: 'Library',
        below: const LibraryTabs(
          tabs: [
            (Key('library-tab-instruments'), 'Instruments'),
            (Key('library-tab-loops'), 'Loops'),
            (Key('library-tab-arrangements'), 'Arrangements'),
          ],
        ),
        child: TabBarView(
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
            UnreadableNote(count: snapshot.unreadableCount),
            if (tags.isNotEmpty) ...[
              const RoundSectionHeader('Filter by tag'),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  TactileChip(
                    key: const Key('filter-all'),
                    label: 'All',
                    selected: tag == null,
                    onPressed: () => setState(() => _tag = null),
                  ),
                  for (final option in tags)
                    TactileChip(
                      key: Key('filter-$option'),
                      label: option,
                      selected: option == tag,
                      onPressed: () => setState(() => _tag = option),
                    ),
                ],
              ),
              const SizedBox(height: Space.lg),
            ],
            const RoundSectionHeader('My instruments'),
            if (mine.isEmpty)
              EmptyNote(
                tag == null
                    ? 'No instruments yet. Save one from the Editor.'
                    : 'None of your instruments has the tag "$tag".',
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
              const RoundSectionHeader('Factory'),
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
    return LibraryCard(
      seed: instrument.id.hashCode & 0xff,
      leading: SizedBox.square(
        dimension: 60,
        child: RoundSurface(
          style: SurfaceStyle.glass,
          shape: RoundShape.circle,
          child: Center(
            child: InstrumentRadarThumbnail(instrument: instrument, size: 48),
          ),
        ),
      ),
      title: instrument.name,
      lines: [
        CardLine(
          '${instrument.harmonics.length} harmonics · '
          '${instrument.decayMs} ms',
        ),
        if (instrument.tags.isNotEmpty)
          Text(
            key: Key('tags-${instrument.id}'),
            instrument.tags.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: roundText(
              context,
              color: textOn(context, SurfaceStyle.organic),
              size: TypeScale.caption,
            ),
          ),
      ],
      onTap: onTap,
      actions: [
        if (onDelete != null)
          RoundIconButton(
            key: Key('delete-${instrument.id}'),
            icon: Icons.delete_outline,
            label: 'Delete ${instrument.name}',
            onPressed: onDelete,
          ),
      ],
    );
  }
}
