// The circular dot pad was replaced by the instrument radar (UX-115). This
// guards against its code coming back half-way: no file and no symbol of it
// is left in the app or the core.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final removed = [
    'lib/features/editor/instrument_pad_view.dart',
    'lib/features/editor/pad_geometry.dart',
    'packages/synesterra_core/lib/src/sound/instrument_pad.dart',
    'packages/synesterra_core/test/instrument_pad_test.dart',
  ];
  final symbols = RegExp(
    r'\b(PadPoint|PadAnchor|PadRecipe|padAnchors|padCenterRecipe|'
    r'instrumentForPad|InstrumentPad|InstrumentPadPainter|padPointAt|'
    r'padOffsetOf|stepPadPoint|setPadPoint|releasePad|startsNewSound)\b|'
    r'instrument_pad|pad_geometry',
  );

  test('the pad files are gone', () {
    for (final path in removed) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  test('no Dart source refers to the pad', () {
    final roots = ['lib', 'packages/synesterra_core/lib'];
    for (final root in roots) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        expect(symbols.hasMatch(text), isFalse, reason: entity.path);
      }
    }
  });
}
