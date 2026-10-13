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
/// gesture ([onEnd]), in the local coordinates of [child]. The gesture is
/// taken at once, so a graph inside a scrolling page is edited by touching it
/// and never scrolls the page.
///
/// A gesture the system cancels (a call, a system gesture) calls [onCancel]
/// when given, otherwise [onEnd]. The pan recognizer reports such a cancel
/// as an ordinary end, so the pointer cancel is noticed here first.
class ImmediatePanDetector extends StatefulWidget {
  const ImmediatePanDetector({
    super.key,
    required this.onDown,
    required this.onUpdate,
    required this.onEnd,
    this.onCancel,
    required this.child,
  });

  final void Function(Offset position) onDown;
  final void Function(Offset position) onUpdate;
  final VoidCallback onEnd;
  final VoidCallback? onCancel;
  final Widget child;

  @override
  State<ImmediatePanDetector> createState() => _ImmediatePanDetectorState();
}

class _ImmediatePanDetectorState extends State<ImmediatePanDetector> {
  bool _cancelled = false;

  void _finish() {
    final cancelled = _cancelled;
    _cancelled = false;
    final onCancel = widget.onCancel;
    if (cancelled && onCancel != null) {
      onCancel();
    } else {
      widget.onEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    // A Listener sees the pointer cancel before the recognizer turns it
    // into an end.
    return Listener(
      onPointerCancel: (_) => _cancelled = true,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _ImmediatePanRecognizer:
              GestureRecognizerFactoryWithHandlers<_ImmediatePanRecognizer>(
                _ImmediatePanRecognizer.new,
                (recognizer) {
                  recognizer.onDown = (details) {
                    _cancelled = false;
                    widget.onDown(details.localPosition);
                  };
                  recognizer.onUpdate = (details) =>
                      widget.onUpdate(details.localPosition);
                  recognizer.onEnd = (_) => _finish();
                  recognizer.onCancel = _finish;
                },
              ),
        },
        child: widget.child,
      ),
    );
  }
}
