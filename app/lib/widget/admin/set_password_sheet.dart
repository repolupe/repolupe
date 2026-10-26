import 'package:app/gen/strings.g.dart';
import 'package:app/service/admin_user_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/validation.dart';
import 'package:app/widget/form_sheet.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Sets a new password for another user (an admin), which signs them out everywhere, and whether they must change
/// it after logging in. Pops with the updated user.
class SetPasswordSheet extends StatefulWidget {
  final UserDto user;

  const SetPasswordSheet({super.key, required this.user});

  /// Returns the updated user, `null` if the sheet was dismissed.
  static Future<UserDto?> show(BuildContext context, {required UserDto user}) async {
    return FormSheet.show<UserDto>(context, builder: (_) => SetPasswordSheet(user: user));
  }

  @override
  State<SetPasswordSheet> createState() => _SetPasswordSheetState();
}

class _SetPasswordSheetState extends State<SetPasswordSheet> with Refena {
  bool _loading = false;
  String _password = '';
  bool _showPassword = false;

  /// On, so they choose their own password.
  bool _mustChangePassword = true;

  /// Why the last try failed, until the next one.
  String? _error;

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.global.dispatchAsync(
        SetUserPasswordAction(id: widget.user.id, password: _password, mustChangePassword: _mustChangePassword),
      );
      if (!mounted) {
        return;
      }
      if (result.user case final user?) {
        Navigator.pop(context, user);
      } else {
        setState(() {
          _error = result.error;
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
    final users = t.base.admin.users;
    return FormSheet(
      title: Text(users.passwordDialog.title),
      description: users.passwordDialog.intro(name: widget.user.userName),
      loading: _loading,
      onSave: _save,
      saveKey: const ValueKey('user.password.save'),
      children: [
        StringField(
          key: const ValueKey('user.password.new'),
          value: _password,
          decoration: InputDecoration(
            labelText: t.base.user.newPassword,
            helperText: t.base.user.passwordHint(min: minPasswordLength, max: maxPasswordLength),
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
              tooltip: _showPassword ? t.flutter.admin.users.hidePassword : t.flutter.admin.users.showPassword,
              onPressed: () {
                setState(() {
                  _showPassword = !_showPassword;
                });
              },
            ),
          ),
          obscureText: !_showPassword,
          keyboardType: TextInputType.visiblePassword,
          enabled: !_loading,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (value) {
            setState(() {
              _password = value;
            });
          },
          onSubmitted: (_) async {
            if (!_loading) {
              await _save();
            }
          },
        ),
        if (_error case final error?) InlineError(error, key: const ValueKey('user.password.error')),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('user.password.mustChange'),
          title: Text(users.mustChangePassword),
          subtitle: Text(users.chooseOwnPasswordHint),
          contentPadding: EdgeInsets.zero,
          value: _mustChangePassword,
          onChanged: _loading
              ? null
              : (value) {
                  setState(() {
                    _mustChangePassword = value;
                  });
                },
        ),
      ],
    );
  }
}
