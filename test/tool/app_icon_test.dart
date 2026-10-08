import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/instrument_figure/figure_spec.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../tool/app_icon.dart';

void main() {
  test('generation is deterministic', () {
    expect(buildTextFiles(), buildTextFiles());
    final a = buildImages();
    final b = buildImages();
    expect(a.keys, b.keys);
    for (final path in a.keys) {
      expect(a[path]!.pixels, b[path]!.pixels, reason: path);
      expect(encodePng(a[path]!), encodePng(b[path]!), reason: path);
    }
  });

  test('committed files match the generator output', () {
    buildTextFiles().forEach((path, text) {
      expect(
        File(path).readAsStringSync().replaceAll('\r\n', '\n'),
        text,
        reason: path,
      );
    });
    buildImages().forEach((path, image) {
      final committed = decodePng(File(path).readAsBytesSync());
      expect(committed.size, image.size, reason: path);
      expect(committed.pixels, image.pixels, reason: path);
    });
  });

  test('palette constants match the Forest tokens', () {
    final source = File('lib/shared/theme/synesterra_theme.dart')
        .readAsStringSync();
    final forest = RegExp(
      r'static const forest = SynesterraTokens\((.*?)\n  \);',
      dotAll: true,
    ).firstMatch(source)!.group(1)!;
    int token(String name) => int.parse(
      RegExp('$name: Color\\(0xff([0-9a-f]{6})\\)')
          .firstMatch(forest)!
          .group(1)!,
      radix: 16,
    );
    expect(forestBackground & 0xffffff, token('background'));
    expect(forestAccent & 0xffffff, token('accent'));
  });

  test('the figure is a closed curve with three lobes', () {
    final radii = [for (final p in figureCurve()) p.magnitude];
    expect(radii.reduce(math.max), closeTo(1, 1e-9));
    var peaks = 0;
    for (var i = 0; i < radii.length; i++) {
      final prev = radii[(i + radii.length - 1) % radii.length];
      final next = radii[(i + 1) % radii.length];
      if (radii[i] > prev && radii[i] >= next) peaks++;
    }
    expect(peaks, 3);
  });

  test('the stroked figure stays inside the adaptive safe zone', () {
    expect(figureRadiusDp + strokeDp / 2, lessThanOrEqualTo(safeRadiusDp));
    final xml =
        buildTextFiles()['android/app/src/main/res/drawable/'
            'ic_launcher_foreground.xml']!;
    final data = RegExp(r'pathData="([^"]+)"').firstMatch(xml)!.group(1)!;
    for (final m in RegExp(r'[ML]([\d.]+),([\d.]+)').allMatches(data)) {
      final x = double.parse(m.group(1)!) - canvasDp / 2;
      final y = double.parse(m.group(2)!) - canvasDp / 2;
      expect(
        math.sqrt(x * x + y * y) + strokeDp / 2,
        lessThanOrEqualTo(safeRadiusDp),
      );
    }
  });

  test('the icon curve matches the app figure maths (drift guard)', () {
    final top = iconHarmonics.keys.reduce(math.max);
    final instrument = Instrument(
      id: 'icon',
      name: 'Icon',
      harmonics: [for (var n = 1; n <= top; n++) iconHarmonics[n] ?? 0.0],
      attackMs: 5,
      decayMs: 200,
    );
    const segments = 360;
    final app = buildFigure(instrument, fundamentalHz: 110, points: segments);
    final icon = figureCurve(segments: segments);
    expect(icon.length, segments);
    for (var i = 0; i < segments; i++) {
      // The icon rotates the figure by -90 degrees: (x, y) -> (y, -x).
      expect(icon[i].x, closeTo(app[i].dy, 1e-9), reason: 'x at $i');
      expect(icon[i].y, closeTo(-app[i].dx, 1e-9), reason: 'y at $i');
    }
  });

  test('the manifest label is Synesterra', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final label = RegExp(r'android:label="([^"]*)"').firstMatch(manifest);
    expect(label!.group(1), 'Synesterra');
  });
}
