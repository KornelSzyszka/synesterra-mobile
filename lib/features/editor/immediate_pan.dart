import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A pan recognizer that wins the gesture at once, so touching a graph
/// edits it instead of scrolling the page it sits in.
class _ImmediatePanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// Reports a touch ([onDown]), its movement ([onUpdate]) and the end of the
/// gesture ([onEnd], also when it is cancelled), in the local coordinates of
/// [child]. The gesture is taken at once, so a graph inside a scrolling page
/// is edited by touching it and never scrolls the page.
class ImmediatePanDetector extends StatelessWidget {
  const ImmediatePanDetector({
    super.key,
    required this.onDown,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  final void Function(Offset position) onDown;
  final void Function(Offset position) onUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _ImmediatePanRecognizer:
            GestureRecognizerFactoryWithHandlers<_ImmediatePanRecognizer>(
              _ImmediatePanRecognizer.new,
              (recognizer) {
                recognizer.onDown = (details) => onDown(details.localPosition);
                recognizer.onUpdate = (details) =>
                    onUpdate(details.localPosition);
                recognizer.onEnd = (_) => onEnd();
                recognizer.onCancel = onEnd;
              },
            ),
      },
      child: child,
    );
  }
}
