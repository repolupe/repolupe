import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Changes the email of the active account, keeping its [userName]. An empty email removes it.
class EmailDialog extends StatefulWidget {
  final String userName;
  final String email;

  const EmailDialog({super.key, required this.userName, required this.email});

  /// Opens the dialog with the current [userName] and [email] (empty if none).
  static Future<void> show(BuildContext context, {required String userName, required String email}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => EmailDialog(userName: userName, email: email),
    );
  }

  @override
  State<EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends State<EmailDialog> with Refena {
  bool _loading = false;
  late String _email = widget.email;

  /// Why the last try failed, until the next one.
  String? _error;

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final error = await ref.global.dispatchAsync(UpdateIdentityAction(userName: widget.userName, email: _email, field: IdentityField.email));
      if (!mounted) {
        return;
      }
      if (error == null) {
        Navigator.pop(context);
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
    final t = context.t;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(t.base.settings.account.emailDialog.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StringField(
            key: const ValueKey('account.emailDialog.email'),
            value: _email,
            label: t.base.user.emailOptional,
            keyboardType: TextInputType.emailAddress,
            enabled: !_loading,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (value) {
              setState(() {
                _email = value;
              });
            },
            onSubmitted: (_) async {
              if (!_loading) {
                await _save();
              }
            },
          ),
          if (_error case final error?) InlineError(error, key: const ValueKey('account.emailDialog.error')),
          const SizedBox(height: 12),
          Text(
            t.base.settings.account.loginHint,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(t.base.common.cancel),
        ),
        FilledButton(
          key: const ValueKey('account.emailDialog.save'),
          onPressed: _loading ? null : _save,
          child: Text(t.base.common.save),
        ),
      ],
    );
  }
}
