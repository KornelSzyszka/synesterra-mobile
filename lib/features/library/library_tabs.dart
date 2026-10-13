import 'package:flutter/material.dart';

import '../../shared/theme/design_scale.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/widgets/round_components.dart';
import '../../shared/widgets/tap_glitch.dart';

/// The Library's tab strip: a tray with the chosen tab raised and tinted
/// gold, like [RoundSegmented], driving the surrounding [DefaultTabController]
/// so that swiping the pages moves it too.
class LibraryTabs extends StatelessWidget {
  const LibraryTabs({super.key, required this.tabs});

  /// Key and label of each tab, in order.
  final List<(Key, String)> tabs;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
      child: SizedBox(
        height: 52,
        child: RoundSurface(
          style: SurfaceStyle.tray,
          padding: const EdgeInsets.all(2),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _TabCell(
                      key: tabs[i].$1,
                      label: tabs[i].$2,
                      selected: controller.index == i,
                      onTap: () => controller.animateTo(i),
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

class _TabCell extends StatelessWidget {
  const _TabCell({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = selected ? SurfaceStyle.tactileSelected : SurfaceStyle.tray;
    final text = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: roundText(
            context,
            color: selected
                ? textOn(context, SurfaceStyle.tactileSelected)
                : mutedTextOn(context, SurfaceStyle.tray),
            weight: FontWeight.w500,
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TapGlitch(
          shape: RoundShape.capsule,
          child: selected
              ? RoundSurface(
                  style: style,
                  child: Center(child: text),
                )
              : Center(child: text),
        ),
      ),
    );
  }
}
