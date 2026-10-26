import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/widget/form_sheet.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Changes the user name of the active account, keeping its [email]. With [showLoginHint] it says that the user logs in
/// with it (not for the local instance, which the app logs in to).
class UserNameSheet extends StatefulWidget {
  final String userName;
  final String email;
  final bool showLoginHint;

  const UserNameSheet({super.key, required this.userName, required this.email, required this.showLoginHint});

  /// Opens the sheet with the current [userName] and [email] (empty if none).
  static Future<void> show(
    BuildContext context, {
    required String userName,
    required String email,
    required bool showLoginHint,
  }) async {
    await FormSheet.show<void>(
      context,
      builder: (_) => UserNameSheet(userName: userName, email: email, showLoginHint: showLoginHint),
    );
  }

  @override
  State<UserNameSheet> createState() => _UserNameSheetState();
}

class _UserNameSheetState extends State<UserNameSheet> with Refena {
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
    return FormSheet(
      title: Text(t.base.settings.account.userNameDialog.title),
      loading: _loading,
      onSave: _save,
      saveKey: const ValueKey('account.userNameDialog.save'),
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
    );
  }
}
