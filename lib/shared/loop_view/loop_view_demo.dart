import 'package:flutter/material.dart';

import '../theme/design_scale.dart';
import '../widgets/design_components.dart';
import 'loop_examples.dart';
import 'loop_view.dart';
import 'loop_view_state.dart';
import 'position_source.dart';

/// A debug harness that shows the 3:2 and 5:4 example loops in all three
/// views, driven by [TutorialClock]s, plus an arrangement strip on a fake
/// position. It is not routed from the app shell: a test, a scratch page or a
/// future debug entry mounts it.
class LoopViewDemo extends StatefulWidget {
  const LoopViewDemo({super.key});

  @override
  State<LoopViewDemo> createState() => _LoopViewDemoState();
}

class _LoopViewDemoState extends State<LoopViewDemo>
    with TickerProviderStateMixin {
  late final _loops = [
    ('3:2', LoopViewState.fromDocument(exampleLoop32())),
    ('5:4', LoopViewState.fromDocument(exampleLoop54())),
  ];

  // 90 BPM: a 4-beat cycle lasts 2.67 s.
  late final _clocks = [
    for (final _ in _loops)
      TutorialClock(
        vsync: this,
        cycleDuration: const Duration(milliseconds: 2667),
      ),
  ];

  final _stripSource = FakePositionSource(
    LoopPosition(
      playing: true,
      cyclePosition: .5,
      cycleIndex: 1,
      sectionIndex: 1,
    ),
  );

  bool _playing = false;

  void _toggle() {
    setState(() => _playing = !_playing);
    for (final clock in _clocks) {
      _playing ? clock.start() : clock.stop();
    }
  }

  @override
  void dispose() {
    for (final clock in _clocks) {
      clock.dispose();
    }
    _stripSource.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(Space.lg),
    children: [
      GoldPrimaryButton(label: _playing ? 'Stop' : 'Play', onPressed: _toggle),
      for (var i = 0; i < _loops.length; i++) ...[
        const SizedBox(height: Space.xl),
        SectionLabel(_loops[i].$1),
        const SizedBox(height: Space.md),
        LoopView(state: _loops[i].$2, source: _clocks[i]),
      ],
      const SizedBox(height: Space.xl),
      const SectionLabel('Arrangement strip'),
      const SizedBox(height: Space.md),
      ArrangementStrip(
        source: _stripSource,
        sections: [
          StripSection(label: 'Verse', repeats: 4),
          StripSection(label: 'Chorus', repeats: 2),
          StripSection(label: 'Gone', repeats: 1, missing: true),
        ],
      ),
    ],
  );
}
