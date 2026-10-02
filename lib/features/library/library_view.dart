import 'package:flutter/material.dart';

import '../../shared/theme/synesterra_theme.dart';

/// Library with one tab per editor panel, in the same order.
class LibraryView extends StatelessWidget {
  const LibraryView({super.key});

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
        body: const TabBarView(
          children: [
            _EmptyTab(text: 'No instruments yet. Save one from the Editor.'),
            _EmptyTab(text: 'No loops yet.'),
            _EmptyTab(text: 'No arrangements yet.'),
          ],
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
