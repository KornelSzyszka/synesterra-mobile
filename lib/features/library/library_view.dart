import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/instrument_library_repository.dart';
import '../../shared/formatting/note_name.dart';
import '../../shared/instrument_mist/instrument_mist.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';

/// Opens an instrument in the editor. [existing] is true for the user's own
/// instruments (edited in place) and false for a factory preset (copied).
typedef OpenInstrument = void Function(Instrument instrument, bool existing);

/// Library with one tab per editor panel, in the same order.
class LibraryView extends StatelessWidget {
  const LibraryView({
    super.key,
    required this.instrumentLibrary,
    required this.onOpenInstrument,
  });

  final InstrumentLibraryRepository instrumentLibrary;
  final OpenInstrument onOpenInstrument;

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
            const _EmptyTab(text: 'No loops yet.'),
            const _EmptyTab(text: 'No arrangements yet.'),
          ],
        ),
      ),
    );
  }
}

class _InstrumentsTab extends StatelessWidget {
  const _InstrumentsTab({required this.library, required this.onOpen});

  final InstrumentLibraryRepository library;
  final OpenInstrument onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return ValueListenableBuilder<InstrumentLibrarySnapshot>(
      valueListenable: library.snapshot,
      builder: (context, snapshot, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (snapshot.unreadableCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                key: const Key('unreadable-note'),
                '${snapshot.unreadableCount} stored '
                '${snapshot.unreadableCount == 1 ? 'file' : 'files'} could '
                'not be read. They were left untouched.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SectionLabel('My instruments'),
          const SizedBox(height: 8),
          if (snapshot.instruments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No instruments yet. Save one from the Editor.',
                style: TextStyle(color: tokens.muted),
              ),
            ),
          for (final instrument in snapshot.instruments)
            _InstrumentTile(
              key: Key('own-${instrument.id}'),
              instrument: instrument,
              onTap: () => onOpen(instrument, true),
              onDelete: () => _delete(context, instrument),
            ),
          const SizedBox(height: 16),
          const SectionLabel('Factory'),
          const SizedBox(height: 8),
          for (final preset in factoryInstruments)
            _InstrumentTile(
              key: Key('factory-tile-${preset.id}'),
              instrument: preset,
              onTap: () => onOpen(preset, false),
            ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, Instrument instrument) async {
    final messenger = ScaffoldMessenger.of(context);
    await library.delete(instrument.id);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${instrument.name}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => library.save(instrument),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: tokens.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.border),
          borderRadius: BorderRadius.circular(7),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  InstrumentMist(instrument: instrument, size: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(instrument.name),
                        Text(
                          '${pitchLabel(instrument.fundamentalHz)} · '
                          '${instrument.harmonics.length} harmonics · '
                          '${instrument.decayMs} ms',
                          style: TextStyle(color: tokens.muted, fontSize: 12),
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

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: tokens.muted),
        ),
      ),
    );
  }
}
