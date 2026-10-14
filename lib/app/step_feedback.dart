import 'dart:async';

import 'package:flutter/services.dart';

/// The light haptic tick the Instrument wheel gives each time a vertex snaps
/// to another step. It lives in the composition root because the UI never
/// reaches the platform itself (decision 0001, R5); the app hands it to the
/// Editor, which hands it to the wheel.
void hapticStepFeedback() => unawaited(HapticFeedback.selectionClick());
