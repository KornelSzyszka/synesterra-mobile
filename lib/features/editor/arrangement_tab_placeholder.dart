import 'package:flutter/material.dart';

import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/design_components.dart';

/// What the Editor's Arrangement tab shows until the Arrangement panel is
/// passed in through `EditorView.arrangementPanel`.
class ArrangementTabPlaceholder extends StatelessWidget {
  const ArrangementTabPlaceholder({super.key});

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
            const SectionLabel('Arrangement'),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Icon(Icons.view_timeline_outlined, color: tokens.accent),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    'Chain loops into a backing track. Planned.',
                    style: TextStyle(color: tokens.muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
