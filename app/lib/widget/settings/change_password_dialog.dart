import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/util/validation.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Changes the password of the active account, which signs out its other sessions.
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const ChangePasswordDialog(),
    );
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> with Refena {
  bool _loading = false;
  String _currentPassword = '';
  String _newPassword = '';
  String _confirmPassword = '';

  /// Why the last try failed, until the next one.
  String? _error;

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final error = await ref
          .redux(meProvider)
          .dispatchAsyncTakeResult(
            ChangePasswordAction(
              currentPassword: _currentPassword,
              newPassword: _newPassword,
              confirmPassword: _confirmPassword,
            ),
          );
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
      title: Text(t.base.settings.account.changePasswordDialog.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StringField(
            key: const ValueKey('account.password.current'),
            value: _currentPassword,
            label: t.base.user.currentPassword,
            obscureText: true,
            enabled: !_loading,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onChanged: (value) {
              setState(() {
                _currentPassword = value;
              });
            },
          ),
          const SizedBox(height: 16),
          StringField(
            key: const ValueKey('account.password.new'),
            value: _newPassword,
            label: t.base.user.newPassword,
            hint: t.base.user.passwordHint(min: minPasswordLength, max: maxPasswordLength),
            obscureText: true,
            enabled: !_loading,
            textInputAction: TextInputAction.next,
            onChanged: (value) {
              setState(() {
                _newPassword = value;
              });
            },
          ),
          const SizedBox(height: 16),
          StringField(
            key: const ValueKey('account.password.confirm'),
            value: _confirmPassword,
            label: t.base.user.confirmPassword,
            obscureText: true,
            enabled: !_loading,
            textInputAction: TextInputAction.done,
            onChanged: (value) {
              setState(() {
                _confirmPassword = value;
              });
            },
            onSubmitted: (_) async {
              if (!_loading) {
                await _save();
              }
            },
          ),
          if (_error case final error?) InlineError(error, key: const ValueKey('account.password.error')),
          const SizedBox(height: 12),
          Text(
            t.base.settings.account.changePasswordDialog.signOutNote,
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
          key: const ValueKey('account.password.save'),
          onPressed: _loading ? null : _save,
          child: Text(t.base.common.save),
        ),
      ],
    );
  }
}
