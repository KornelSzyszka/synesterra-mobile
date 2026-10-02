import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/instrument_library_repository.dart';
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
            if (tags.isNotEmpty) ...[
              const SectionLabel('Filter by tag'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
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
              const SizedBox(height: 16),
            ],
            const SectionLabel('My instruments'),
            const SizedBox(height: 8),
            if (mine.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
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
              const SizedBox(height: 16),
              const SectionLabel('Factory'),
              const SizedBox(height: 8),
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
                          '${instrument.harmonics.length} harmonics · '
                          '${instrument.decayMs} ms',
                          style: TextStyle(color: tokens.muted, fontSize: 12),
                        ),
                        if (instrument.tags.isNotEmpty)
                          Text(
                            key: Key('tags-${instrument.id}'),
                            instrument.tags.join(' · '),
                            style: TextStyle(
                              color: tokens.accent,
                              fontSize: 12,
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
