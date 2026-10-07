import 'package:flutter/material.dart';

import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';

/// Stands in for the Loop and Arrangement panels until they exist (later
/// prototype v0 tasks). The app shell opens it from the Library.
class LibraryItemPlaceholderView extends StatelessWidget {
  const LibraryItemPlaceholderView({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('library-item-placeholder'),
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: SynesterraTokens.of(context).muted),
          ),
        ),
      ),
    );
  }
}
