import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Changes the user name and email of the active account, which the user logs in with.
class IdentityDialog extends StatefulWidget {
  final String userName;
  final String email;

  const IdentityDialog({super.key, required this.userName, required this.email});

  /// Opens the dialog with the current [userName] and [email] (empty if none).
  static Future<void> show(BuildContext context, {required String userName, required String email}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => IdentityDialog(userName: userName, email: email),
    );
  }

  @override
  State<IdentityDialog> createState() => _IdentityDialogState();
}

class _IdentityDialogState extends State<IdentityDialog> with Refena {
  bool _loading = false;
  late String _userName = widget.userName;
  late String _email = widget.email;

  /// Why the last try failed, until the next one.
  String? _error;

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final error = await ref.global.dispatchAsync(UpdateIdentityAction(userName: _userName, email: _email));
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
      title: Text(t.base.settings.account.identityDialog.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StringField(
            key: const ValueKey('account.identity.userName'),
            value: _userName,
            label: t.base.user.userName,
            enabled: !_loading,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onChanged: (value) {
              setState(() {
                _userName = value;
              });
            },
          ),
          const SizedBox(height: 16),
          StringField(
            key: const ValueKey('account.identity.email'),
            value: _email,
            label: t.base.user.emailOptional,
            keyboardType: TextInputType.emailAddress,
            enabled: !_loading,
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
          if (_error case final error?) InlineError(error, key: const ValueKey('account.identity.error')),
          const SizedBox(height: 12),
          Text(
            t.base.settings.account.identityDialog.loginHint,
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
          key: const ValueKey('account.identity.save'),
          onPressed: _loading ? null : _save,
          child: Text(t.base.common.save),
        ),
      ],
    );
  }
}
