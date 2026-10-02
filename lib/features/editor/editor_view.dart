import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../data/repositories/instrument_audition_repository.dart';
import '../../data/repositories/instrument_library_repository.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';
import 'instrument_editor_view_model.dart';
import 'instrument_panel.dart';
import '../../shared/theme/design_scale.dart';

/// Editor with three panels. Instrument is real; Loop and Arrangement are
/// placeholders until their turn.
class EditorView extends StatefulWidget {
  const EditorView({
    super.key,
    required this.instrumentLibrary,
    required this.instrumentAudition,
    this.initialInstrument,
    this.editsExisting = false,
  });

  final InstrumentLibraryRepository instrumentLibrary;
  final InstrumentAuditionRepository instrumentAudition;

  /// Null starts a new instrument.
  final Instrument? initialInstrument;

  /// True when [initialInstrument] comes from the library and is edited in
  /// place; false makes a copy (a factory preset).
  final bool editsExisting;

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  late final InstrumentEditorViewModel _instrument = InstrumentEditorViewModel(
    repository: widget.instrumentLibrary,
    audition: widget.instrumentAudition,
    instrument: widget.initialInstrument,
    existing: widget.editsExisting,
  );

  @override
  void dispose() {
    _instrument.dispose();
    super.dispose();
  }

  /// Leaving with unsaved changes asks first; the safe answer is Cancel.
  Future<void> _confirmLeave() async {
    final navigator = Navigator.of(context);
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save this instrument before leaving?'),
        actions: [
          TextButton(
            key: const Key('leave-discard'),
            onPressed: () => Navigator.pop(context, _LeaveChoice.discard),
            child: const Text('Discard'),
          ),
          TextButton(
            key: const Key('leave-cancel'),
            autofocus: true,
            onPressed: () => Navigator.pop(context, _LeaveChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('leave-save'),
            onPressed: _instrument.canSave
                ? () => Navigator.pop(context, _LeaveChoice.save)
                : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
    switch (choice) {
      case _LeaveChoice.discard:
        navigator.pop();
      case _LeaveChoice.save:
        if (await _instrument.save()) navigator.pop();
      case _LeaveChoice.cancel || null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _instrument,
      builder: (context, _) => PopScope(
        canPop: !_instrument.dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Editor'),
              bottom: const TabBar(
                tabs: [
                  Tab(key: Key('editor-tab-instrument'), text: 'Instrument'),
                  Tab(key: Key('editor-tab-loop'), text: 'Loop'),
                  Tab(key: Key('editor-tab-arrangement'), text: 'Arrangement'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _KeepAlive(child: InstrumentPanel(viewModel: _instrument)),
                const _KeepAlive(
                  child: _PlaceholderPanel(
                    icon: Icons.blur_circular,
                    title: 'Loop',
                    text: 'Layers with an instrument each. Planned.',
                  ),
                ),
                const _KeepAlive(
                  child: _PlaceholderPanel(
                    icon: Icons.view_timeline_outlined,
                    title: 'Arrangement',
                    text: 'Chain loops into a backing track. Planned.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _LeaveChoice { save, discard, cancel }

/// Keeps a panel's state when the user switches to another panel.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _PlaceholderPanel extends StatelessWidget {
  const _PlaceholderPanel({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: DesignPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(title),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Icon(icon, color: tokens.accent),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(text, style: TextStyle(color: tokens.muted)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
