import 'package:flutter/widgets.dart';

import 'position_source.dart';

/// Gives [child] one semantics label that follows [source] without rebuilding
/// the child on every position update: the label is recomputed on each change
/// but the subtree is rebuilt only when the text differs (for example when
/// play starts, not on every frame).
class SourceSemantics extends StatefulWidget {
  const SourceSemantics({
    super.key,
    required this.source,
    required this.label,
    required this.child,
  });

  final PositionSource source;

  /// The label for a position. Must depend only on what screen reader users
  /// need (playing, section), not on the exact cycle position.
  final String Function(LoopPosition position) label;
  final Widget child;

  @override
  State<SourceSemantics> createState() => _SourceSemanticsState();
}

class _SourceSemanticsState extends State<SourceSemantics> {
  late String _label = widget.label(widget.source.value);

  @override
  void initState() {
    super.initState();
    widget.source.addListener(_onPosition);
  }

  @override
  void didUpdateWidget(covariant SourceSemantics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      oldWidget.source.removeListener(_onPosition);
      widget.source.addListener(_onPosition);
    }
    _label = widget.label(widget.source.value);
  }

  @override
  void dispose() {
    widget.source.removeListener(_onPosition);
    super.dispose();
  }

  void _onPosition() {
    final next = widget.label(widget.source.value);
    if (next != _label) setState(() => _label = next);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: _label,
    child: ExcludeSemantics(child: widget.child),
  );
}
