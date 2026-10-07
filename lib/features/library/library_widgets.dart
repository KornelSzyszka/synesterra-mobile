import 'package:flutter/material.dart';

import '../../data/repositories/library_item.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';

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

/// Muted explanatory text for an empty list.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.md),
    child: Text(
      text,
      style: TextStyle(color: SynesterraTokens.of(context).muted),
    ),
  );
}

/// A tappable card with a leading picture, a title, summary lines and
/// trailing actions.
class LibraryCard extends StatelessWidget {
  const LibraryCard({
    super.key,
    required this.leading,
    required this.title,
    required this.lines,
    required this.onTap,
    this.actions = const [],
  });

  final Widget leading;
  final String title;
  final List<Widget> lines;
  final VoidCallback onTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Material(
        color: tokens.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.border),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.sm,
                Space.xs,
                Space.sm,
              ),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(title), ...lines],
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A caption-sized line under a card title.
class CardLine extends StatelessWidget {
  const CardLine(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: color ?? SynesterraTokens.of(context).muted,
      fontSize: TypeScale.caption,
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
