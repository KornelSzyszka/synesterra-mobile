// Visual language v2 on the Arrangement panel (UX-119): round components,
// 48 dp labelled controls, no live blur and 4.5:1 text on every surface.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/in_memory_arrangement_library_repository.dart';
import 'package:synesterra/data/repositories/impl/in_memory_loop_library_repository.dart';
import 'package:synesterra/features/arrangement/arrangement_panel.dart';
import 'package:synesterra/shared/loop_view/position_source.dart';
import 'package:synesterra/shared/theme/ground_palette.dart';
import 'package:synesterra/shared/theme/round_shapes.dart';
import 'package:synesterra/shared/theme/surfaces.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/widgets/round_components.dart';

import 'arrangement_fakes.dart';

Future<void> _pumpPanel(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.graphite),
      home: Scaffold(
        body: ArrangementPanel(
          loops: InMemoryLoopLibraryRepository([userLoop('mine', 'My loop')]),
          arrangements: InMemoryArrangementLibraryRepository(),
          playback: RecordingPlayback(),
          position: FakePositionSource(),
          initial: arrangementOf('a1', 'Song', [
            ('factory-loop-3-2', 2),
            ('gone', 1),
          ]),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the Arrangement panel is built from the round components', (
    tester,
  ) async {
    await _pumpPanel(tester);
    final panel = find.byKey(const Key('arrangement-panel'));

    final play = find.byKey(const Key('arrangement-play'));
    expect(
      find.descendant(of: play, matching: find.byType(RoundActionButton)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: play, matching: find.byType(GlassPanel)),
      findsOne,
    );
    final repeat = tester.widget<RoundIconButton>(
      find.byKey(const Key('arrangement-repeat-all')),
    );
    expect(repeat.selected, isFalse, reason: 'a toggle, off by default');
    for (final key in [
      'arrangement-new',
      'arrangement-open',
      'arrangement-save',
      'arrangement-add-section',
    ]) {
      expect(tester.widget(find.byKey(Key(key))), isA<TactileChip>());
    }
    for (final key in ['section-remove-0', 'section-up-1', 'section-down-0']) {
      expect(tester.widget(find.byKey(Key(key))), isA<RoundIconButton>());
    }
    final card = tester.widget<RoundSurface>(
      find
          .descendant(
            of: find.byKey(const Key('section-0')),
            matching: find.byType(RoundSurface),
          )
          .first,
    );
    expect(card.style, SurfaceStyle.organic);
    expect(card.shape, isA<PebbleShape>());
    for (final type in [
      FilledButton,
      OutlinedButton,
      TextButton,
      IconButton,
      Switch,
    ]) {
      expect(
        find.descendant(of: panel, matching: find.byType(type)),
        findsNothing,
        reason: '$type',
      );
    }
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('every control is 48 dp and labelled', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpPanel(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  test('every text colour of the panel keeps its contrast', () {
    for (final palette in SynesterraPalette.values) {
      final theme = synesterraTheme(palette);
      final tokens = theme.extension<SynesterraTokens>()!;
      final error = theme.colorScheme.error;
      // The panel's colours come from the Editor's ground (first layer
      // colour as the mist), the same as the round components' fallback.
      final ground = GroundPalette.of(
        tokens,
        GroundTone.dark,
        tokens.layerColors.first,
      );
      final s = Surfaces(ground);
      final organic = s.fillSamples(SurfaceStyle.organic);
      final glass = s.fillSamples(SurfaceStyle.glass);
      final tray = s.fillSamples(SurfaceStyle.tray);
      final pairs = [
        TextContrastPair('name on ground', ground.text, ground.groundSamples),
        TextContrastPair('note on ground', ground.muted, ground.groundSamples),
        TextContrastPair('error on ground', error, ground.groundSamples),
        TextContrastPair(
          'tempo and captions on glass',
          s.mutedOn(SurfaceStyle.glass),
          glass,
        ),
        TextContrastPair(
          'loop name on a section',
          s.textOn(SurfaceStyle.organic),
          organic,
        ),
        TextContrastPair(
          'summary on a section',
          s.mutedOn(SurfaceStyle.organic),
          organic,
        ),
        TextContrastPair('missing loop on a section', error, organic),
        TextContrastPair('section number on its orb', ground.text, [
          for (final c in organic)
            Color.alphaBlend(ground.accent.withValues(alpha: .08), c),
        ]),
        TextContrastPair('repeats on tray', tokens.text, tray),
        TextContrastPair('repeats unit on tray', tokens.muted, tray),
        TextContrastPair(
          'chip',
          s.textOn(SurfaceStyle.tactile),
          s.fillSamples(SurfaceStyle.tactile),
        ),
        TextContrastPair(
          'gold chip',
          s.textOn(SurfaceStyle.primary),
          s.fillSamples(SurfaceStyle.primary),
        ),
      ];
      for (final pair in pairs) {
        expect(
          pair.worstContrast,
          greaterThanOrEqualTo(4.5),
          reason: '${palette.name}: ${pair.name}',
        );
      }
    }
  });
}
