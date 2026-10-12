import 'dart:math' as math;
import 'dart:ui';

import 'lab_palette.dart';

/// The three directions compared in the lab.
enum LabVariant {
  glass('Glass'),
  organic('Organic'),
  material('Material');

  const LabVariant(this.label);
  final String label;
}

/// The outline family of an element: a circle, or a wide form for cards,
/// chips, bars and tracks.
enum LabForm { round, wide }

/// What a surface is for. Each skin paints every kind in its own way.
enum LabKind {
  /// A quiet surface: chips, cards, the transport bar.
  plain,

  /// A step above plain: the sheet, the vessel of a card.
  raised,

  /// A chosen chip or segment.
  selected,

  /// The primary action (gold).
  accent,

  /// A groove or tray that holds other elements.
  recessed,
}

/// One visual direction: shapes, surfaces, the pad, the slider track, the
/// sheet and the tap flash. Widgets in `lab_components.dart` are shared; only
/// the skin differs. All lengths here are local to the lab.
abstract class LabSkin {
  const LabSkin(this.palette);

  final LabPalette palette;

  LabVariant get variant;

  /// One line that says what the direction is.
  String get tagline;

  /// True when the primary action breathes with the slow drift.
  bool get primaryBreathes => false;

  /// True when the segmented control is separate elements, not a track.
  bool get separateSegments => false;

  /// The kind of the track behind a segmented control.
  LabKind get segmentTrackKind => LabKind.plain;

  /// The outline of an element in [rect]. [breath] is the drift phase in
  /// radians; skins that do not breathe ignore it.
  Path outline(Rect rect, LabForm form, {int seed = 0, double breath = 0});

  /// Paints the surface of [kind] filling [path] (inside [rect]).
  void paintSurface(
    Canvas canvas,
    Path path,
    Rect rect,
    LabKind kind, {
    bool pressed = false,
    int seed = 0,
  });

  /// The opaque colours text can sit on, on a surface of [kind]: gradient
  /// stops, highlights and translucency over every ground sample. The
  /// painter uses the same colours, so the contrast test checks what is drawn.
  List<Color> fillSamples(LabKind kind);

  Color textOn(LabKind kind) => switch (kind) {
    LabKind.accent => palette.onAccent,
    _ => palette.text,
  };

  Color mutedOn(LabKind kind) => palette.muted;

  /// The slider track in [rect] (the full 48 dp row) at [value] 0..1, and its
  /// thumb.
  void paintTrack(Canvas canvas, Rect rect, double value);

  /// The pad: a disc in [rect] with the instrument mist ([paintMist] draws it
  /// into a square) and the light at [dot] (-1..1 in both axes). [breath] in
  /// radians.
  void paintPad(
    Canvas canvas,
    Rect rect, {
    required void Function(Canvas canvas, Rect square) paintMist,
    required Offset dot,
    required double breath,
  });

  /// The small mark in front of a section header.
  void paintMark(Canvas canvas, Rect rect);

  /// The outline of a bottom sheet in [rect] (open at the bottom edge).
  Path sheetOutline(Rect rect);

  /// The variant's tap flash at progress [t] 0..1 with strength [amount]
  /// 0..1, inside [path]. Must stay subtle and end clean at t = 1.
  void paintGlitch(
    Canvas canvas,
    Path path,
    Rect rect,
    double t,
    double amount,
    int seed,
  );

  /// The reduce-motion replacement: a plain fade of light, no movement.
  void paintFade(Canvas canvas, Path path, double t, double amount) {
    final alpha = (palette.isDark ? .16 : .22) * amount * (1 - t);
    canvas.drawPath(
      path,
      Paint()..color = palette.accent.withValues(alpha: alpha),
    );
  }

  /// Every text colour of this skin with the surfaces it is drawn on.
  List<LabTextPair> textPairs() {
    final name = '${variant.label}/${palette.tone.label}';
    final grounds = palette.groundSamples;
    return [
      LabTextPair('$name text on ground', palette.text, grounds),
      LabTextPair('$name muted on ground', palette.muted, grounds),
      LabTextPair('$name accent text on ground', palette.accentText, grounds),
      for (final (kind, roles) in _drawnText)
        for (final muted in roles)
          LabTextPair(
            '$name ${muted ? 'muted' : 'text'} on ${kind.name}',
            muted ? mutedOn(kind) : textOn(kind),
            fillSamples(kind),
          ),
    ];
  }
}

/// Which text roles the components draw on each kind (false = text, true =
/// muted): titles and values on plain and raised, secondary lines on plain
/// and raised, labels of chosen chips and segments on selected, the primary
/// label on accent, unselected segment labels on the track.
const _drawnText = [
  (LabKind.plain, [false, true]),
  (LabKind.raised, [false, true]),
  (LabKind.selected, [false]),
  (LabKind.accent, [false]),
  (LabKind.recessed, [true]),
];

/// [color] at [alpha] composited over each of [grounds].
List<Color> veiled(Color color, double alpha, List<Color> grounds) => [
  for (final ground in grounds)
    Color.alphaBlend(color.withValues(alpha: alpha), ground),
];

/// A deterministic random generator for one flash or one surface.
math.Random labRandom(int seed) => math.Random(seed * 7919 + 17);
