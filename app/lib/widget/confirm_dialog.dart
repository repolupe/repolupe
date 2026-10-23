import 'package:app/gen/strings.g.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';

/// Confirms an action, then runs [onConfirm], which returns why it failed (`null` if it succeeded); the dialog
/// shows that and stays open then, so it can be tried again.
class ConfirmDialog extends StatefulWidget {
  final String title;
  final String text;
  final String confirmText;
  final IconData confirmIcon;
  final Future<String?> Function() onConfirm;

  /// The key of the confirm button; the error is `<confirmKey>.error`.
  final String confirmKey;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.text,
    required this.confirmText,
    required this.confirmIcon,
    required this.onConfirm,
    required this.confirmKey,
  });

  /// Returns whether it was confirmed and [onConfirm] succeeded.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String text,
    required String confirmText,
    required IconData confirmIcon,
    required Future<String?> Function() onConfirm,
    required String confirmKey,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(
        title: title,
        text: text,
        confirmText: confirmText,
        confirmIcon: confirmIcon,
        onConfirm: onConfirm,
        confirmKey: confirmKey,
      ),
    );
    return confirmed ?? false;
  }

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  bool _loading = false;

  /// Why the last try failed, until the next one.
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final error = await widget.onConfirm();
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
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.text),
          if (_error case final error?) InlineError(error, key: ValueKey('${widget.confirmKey}.error')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: Text(context.t.base.common.cancel),
        ),
        FilledButton.icon(
          key: ValueKey(widget.confirmKey),
          onPressed: _loading ? null : _confirm,
          icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(widget.confirmIcon),
          label: Text(widget.confirmText),
        ),
      ],
    );
  }
}
