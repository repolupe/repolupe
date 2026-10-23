import 'package:app/gen/strings.g.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';

/// Confirms deleting something by typing its name ([verify]), then runs [onDelete], which returns why it failed
/// (`null` if it succeeded); the dialog shows that and stays open then, so it can be tried again.
class DeleteDialog extends StatefulWidget {
  final String title;
  final String text;
  final String verify;
  final Future<String?> Function() onDelete;

  /// The prefix of the keys of the field (`<prefix>.verification`) and the button (`<prefix>.confirm`).
  final String keyPrefix;

  const DeleteDialog({
    super.key,
    required this.title,
    required this.text,
    required this.verify,
    required this.onDelete,
    required this.keyPrefix,
  });

  /// Returns whether it was deleted.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String text,
    required String verify,
    required Future<String?> Function() onDelete,
    required String keyPrefix,
  }) async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteDialog(title: title, text: text, verify: verify, onDelete: onDelete, keyPrefix: keyPrefix),
    );
    return deleted ?? false;
  }

  @override
  State<DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<DeleteDialog> {
  bool _loading = false;
  String _input = '';

  /// Why the last try failed, until the next one.
  String? _error;

  bool get _verified => _input.trim() == widget.verify;

  Future<void> _delete() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final error = await widget.onDelete();
      if (!mounted) {
        return;
      }
      if (error == null) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _error = error;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.text),
            const SizedBox(height: 16),
            Text(
              context.t.base.app.genericDeleteDialog.verifyPrompt(verify: widget.verify),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            StringField(
              key: ValueKey('${widget.keyPrefix}.verification'),
              value: _input,
              label: context.t.base.app.genericDeleteDialog.verification,
              enabled: !_loading,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (value) {
                setState(() {
                  _input = value;
                });
              },
              onSubmitted: (_) async {
                if (_verified && !_loading) {
                  await _delete();
                }
              },
            ),
            if (_error case final error?) InlineError(error, key: ValueKey('${widget.keyPrefix}.error')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: Text(context.t.base.common.cancel),
        ),
        FilledButton.icon(
          key: ValueKey('${widget.keyPrefix}.confirm'),
          onPressed: _verified && !_loading ? _delete : null,
          icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete),
          label: Text(context.t.base.common.delete),
        ),
      ],
    );
  }
}
