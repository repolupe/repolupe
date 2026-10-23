import 'package:app/gen/strings.g.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/util/validation.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Changes the password of a user who must change it before they can do anything else (`HomePage` shows it
/// instead of the chat until then). The user can only log out instead.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> with Refena {
  bool _loading = false;
  String _currentPassword = '';
  String _newPassword = '';
  String _confirmPassword = '';

  bool get _canSubmit => !_loading && _currentPassword.isNotEmpty && _newPassword.isNotEmpty && _confirmPassword.isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
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
      if (error != null) {
        ref.global.dispatch(ShowSnackBarAction(message: error));
      }
    } finally {
      // After a successful change, the home page shows the chat instead.
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
    return Scaffold(
      appBar: AppBar(
        title: Text(t.base.login.changePasswordPage.title),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.flutter.settings.changePasswordPage.intro),
                  const SizedBox(height: 24),
                  StringField(
                    key: const ValueKey('changePassword.current'),
                    value: _currentPassword,
                    label: t.base.user.currentPassword,
                    obscureText: true,
                    enabled: !_loading,
                    textInputAction: TextInputAction.next,
                    onChanged: (value) {
                      setState(() {
                        _currentPassword = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  StringField(
                    key: const ValueKey('changePassword.new'),
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
                    key: const ValueKey('changePassword.confirm'),
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
                      if (_canSubmit) {
                        await _submit();
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  OverflowBar(
                    alignment: MainAxisAlignment.spaceBetween,
                    spacing: 8,
                    overflowAlignment: OverflowBarAlignment.end,
                    children: [
                      TextButton(
                        key: const ValueKey('changePassword.logout'),
                        onPressed: _loading
                            ? null
                            : () async {
                                await ref.redux(accountProvider).dispatchAsync(LogoutAction());
                              },
                        child: Text(t.base.login.changePasswordPage.logout),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('changePassword.submit'),
                        onPressed: _canSubmit ? _submit : null,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.arrow_forward),
                        label: Text(t.base.login.changePasswordPage.submit),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
