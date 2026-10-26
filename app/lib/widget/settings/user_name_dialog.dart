import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Changes the user name of the active account, keeping its [email]. With [showLoginHint] it says that the user logs in
/// with it (not for the local instance, which the app logs in to).
class UserNameDialog extends StatefulWidget {
  final String userName;
  final String email;
  final bool showLoginHint;

  const UserNameDialog({super.key, required this.userName, required this.email, required this.showLoginHint});

  /// Opens the dialog with the current [userName] and [email] (empty if none).
  static Future<void> show(
    BuildContext context, {
    required String userName,
    required String email,
    required bool showLoginHint,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => UserNameDialog(userName: userName, email: email, showLoginHint: showLoginHint),
    );
  }

  @override
  State<UserNameDialog> createState() => _UserNameDialogState();
}

class _UserNameDialogState extends State<UserNameDialog> with Refena {
  bool _loading = false;
  late String _userName = widget.userName;

  /// Why the last try failed, until the next one.
  String? _error;

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final error = await ref.global.dispatchAsync(UpdateIdentityAction(userName: _userName, email: widget.email, field: IdentityField.userName));
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
      title: Text(t.base.settings.account.userNameDialog.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StringField(
            key: const ValueKey('account.userNameDialog.userName'),
            value: _userName,
            label: t.base.user.userName,
            enabled: !_loading,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (value) {
              setState(() {
                _userName = value;
              });
            },
            onSubmitted: (_) async {
              if (!_loading) {
                await _save();
              }
            },
          ),
          if (_error case final error?) InlineError(error, key: const ValueKey('account.userNameDialog.error')),
          if (widget.showLoginHint) ...[
            const SizedBox(height: 12),
            Text(
              t.base.settings.account.loginHint,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(t.base.common.cancel),
        ),
        FilledButton(
          key: const ValueKey('account.userNameDialog.save'),
          onPressed: _loading ? null : _save,
          child: Text(t.base.common.save),
        ),
      ],
    );
  }
}
