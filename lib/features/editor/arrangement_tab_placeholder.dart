import 'package:flutter/material.dart';

import '../../shared/theme/design_scale.dart';
import '../../shared/widgets/round_components.dart';
import 'editor_style.dart';

/// What the Editor's Arrangement tab shows until the Arrangement panel is
/// passed in through `EditorView.arrangementPanel`.
class ArrangementTabPlaceholder extends StatelessWidget {
  const ArrangementTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SoftHeader('Arrangement'),
          const SizedBox(height: Space.lg),
          Text(
            'Chain loops into a backing track. Planned.',
            style: roundText(context, color: groundOf(context).muted),
          ),
        ],
      ),
    );
  }
}
