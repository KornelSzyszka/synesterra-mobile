import 'package:flutter/material.dart';

import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';

/// Editor with three panels. Only the panel titles are fixed here; each panel
/// replaces its placeholder when its turn comes.
class EditorView extends StatelessWidget {
  const EditorView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
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
        body: const TabBarView(
          children: [
            _KeepAlive(
              child: _PlaceholderPanel(
                icon: Icons.graphic_eq,
                title: 'Instrument',
                text: 'Shape the sound: harmonics, envelope and EQ.',
              ),
            ),
            _KeepAlive(
              child: _PlaceholderPanel(
                icon: Icons.blur_circular,
                title: 'Loop',
                text: 'Layers with an instrument each. Planned.',
              ),
            ),
            _KeepAlive(
              child: _PlaceholderPanel(
                icon: Icons.view_timeline_outlined,
                title: 'Arrangement',
                text: 'Chain loops into a backing track. Planned.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.all(16),
      child: DesignPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(title),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(icon, color: tokens.accent),
                const SizedBox(width: 12),
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
