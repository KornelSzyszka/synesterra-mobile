import 'package:flutter/foundation.dart';

import '../../shared/loop_view/arrangement_strip.dart';
import '../../shared/loop_view/position_source.dart';

/// Turns a [TutorialClock]-like cycle clock into an arrangement position:
/// the section advances after its repeats and the whole arrangement wraps.
/// No audio and no transport; it only reads [source] and never disposes it.
class SectionClock extends ValueNotifier<LoopPosition>
    implements PositionSource {
  SectionClock({required this.source, required this.sections})
    : super(LoopPosition.stopped) {
    if (sections.isEmpty) throw ArgumentError.value(sections, 'sections');
    source.addListener(_update);
    _update();
  }

  final PositionSource source;
  final List<StripSection> sections;

  /// The section and the cycle inside it after [cycles] whole cycles.
  static (int, int) locate(int cycles, List<StripSection> sections) {
    final total = sections.fold<int>(0, (sum, s) => sum + s.repeats);
    var left = cycles % total;
    for (var i = 0; i < sections.length; i++) {
      if (left < sections[i].repeats) return (i, left);
      left -= sections[i].repeats;
    }
    return (0, 0);
  }

  void _update() {
    final base = source.value;
    if (!base.playing) {
      value = LoopPosition(generation: base.generation);
      return;
    }
    final (section, cycle) = locate(base.cycleIndex, sections);
    value = LoopPosition(
      playing: true,
      cyclePosition: base.cyclePosition,
      cycleIndex: cycle,
      generation: base.generation,
      sectionIndex: section,
    );
  }

  @override
  void dispose() {
    source.removeListener(_update);
    super.dispose();
  }
}
