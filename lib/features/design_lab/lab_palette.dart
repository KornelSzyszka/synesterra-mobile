// The lab's palette and contrast maths moved to the shared visual language
// (UX-112); the lab keeps its own names for them.
import '../../shared/theme/ground_palette.dart';

export '../../shared/theme/ground_palette.dart' show contrastRatio;

/// Light or dark ground for the lab.
typedef LabTone = GroundTone;

/// The lab's colours for one palette and tone.
typedef LabPalette = GroundPalette;

/// A text colour and every opaque colour it may be drawn on.
typedef LabTextPair = TextContrastPair;
