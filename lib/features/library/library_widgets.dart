import 'package:flutter/material.dart';

import '../../data/repositories/library_item.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/widgets/round_components.dart';

// Pieces shared by the Loops and Arrangements tabs.

/// Says how many stored files were skipped. Nothing when there are none.
class UnreadableNote extends StatelessWidget {
  const UnreadableNote({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Text(
        key: const Key('unreadable-note'),
        count == 1
            ? '1 stored file could not be read. It was left untouched.'
            : '$count stored files could not be read. They were left '
                  'untouched.',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

/// An empty list explains itself in a quiet glass capsule: a small gold
/// light and a muted line.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.md),
    child: GlassPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xl,
        vertical: Space.lg,
      ),
      child: Row(
        children: [
          CustomPaint(
            size: const Size.square(14),
            painter: _LightPainter(groundOf(context).accent),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Text(
              text,
              style: roundText(
                context,
                color: mutedTextOn(context, SurfaceStyle.glass),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _LightPainter extends CustomPainter {
  const _LightPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas
      ..drawCircle(
        c,
        6,
        Paint()
          ..color = color.withValues(alpha: .4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawCircle(c, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LightPainter old) => old.color != color;
}

/// A library item: a soft organic card with a leading picture, a title,
/// summary lines and trailing round actions. Tapping it opens the item.
class LibraryCard extends StatelessWidget {
  const LibraryCard({
    super.key,
    required this.leading,
    required this.title,
    required this.lines,
    required this.onTap,
    this.actions = const [],
    this.seed = 7,
  });

  final Widget leading;
  final String title;
  final List<Widget> lines;
  final VoidCallback onTap;
  final List<Widget> actions;

  /// Gives neighbouring cards slightly different edges.
  final int seed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: OrganicCard(
        label: title,
        onTap: onTap,
        seed: seed,
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          Space.md,
          Space.md,
          Space.md,
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: Space.lg),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: roundText(
                        context,
                        color: textOn(context, SurfaceStyle.organic),
                        size: TypeScale.bodyLarge,
                        serif: true,
                      ),
                    ),
                    ...lines,
                  ],
                ),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// The round picture at the left of a card: a glass disc with an icon.
class CardBadge extends StatelessWidget {
  const CardBadge({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 52,
    child: RoundSurface(
      style: SurfaceStyle.glass,
      shape: RoundShape.circle,
      child: Center(
        child: Icon(icon, color: groundOf(context).accent, size: 24),
      ),
    ),
  );
}

/// A caption-sized line under a card title.
class CardLine extends StatelessWidget {
  const CardLine(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: roundText(
      context,
      color: color ?? mutedTextOn(context, SurfaceStyle.organic),
      size: TypeScale.caption,
    ),
  );
}

/// Deletes through [delete] and offers Undo, which calls [restore].
Future<void> deleteWithUndo(
  BuildContext context, {
  required String name,
  required Future<void> Function() delete,
  required Future<void> Function() restore,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  await delete();
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text('Deleted "$name"'),
        action: SnackBarAction(label: 'Undo', onPressed: restore),
      ),
    );
}

/// Asks for a new name. Returns it, or null when the user cancels or keeps
/// the old one. Save is enabled only for a valid library name.
Future<String?> showRenameDialog(
  BuildContext context, {
  required String title,
  required String initial,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(title: title, initial: initial),
  );
  return name == null || name == initial ? null : name;
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name => _controller.text.trim();

  @override
  Widget build(BuildContext context) {
    final valid = isValidLibraryName(_name);
    void save() => Navigator.of(context).pop(_name);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('rename-field'),
        controller: _controller,
        autofocus: true,
        maxLength: maxLibraryNameLength,
        decoration: const InputDecoration(labelText: 'Name'),
        onChanged: (_) => setState(() {}),
        onSubmitted: valid ? (_) => save() : null,
      ),
      actions: [
        TextButton(
          key: const Key('rename-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('rename-save'),
          onPressed: valid ? save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
