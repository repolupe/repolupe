import 'package:app/gen/strings.g.dart';
import 'package:app/service/admin_user_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/validation.dart';
import 'package:app/widget/unsaved_changes_guard.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Creates a user (user name, email, password, whether they must change it), or edits [user] (user name, email and
/// permissions; admins cannot be restricted, a CHECK on the server enforces it). Pops with the created or updated
/// user.
class UserFormPage extends StatefulWidget {
  /// The user being edited, `null` when creating one.
  final UserDto? user;

  const UserFormPage.create({super.key}) : user = null;

  const UserFormPage.edit({super.key, required UserDto this.user});

  @override
  State<UserFormPage> createState() => _UserFormPageState();
}

class _UserFormPageState extends State<UserFormPage> with Refena {
  bool _saving = false;
  late String _userName = widget.user?.userName ?? '';
  late String _email = widget.user?.email ?? '';
  String _password = '';
  bool _showPassword = false;
  late bool _canLogin = widget.user?.canLogin ?? true;
  late bool _canManageRepositories = widget.user?.canManageRepositories ?? true;
  late bool _canChangeIdentity = widget.user?.canChangeIdentity ?? true;

  /// On for a new user, so they choose their own password.
  late bool _mustChangePassword = widget.user?.mustChangePassword ?? true;

  bool get _isEdit => widget.user != null;
  bool get _isAdmin => widget.user?.role == UserRole.admin;

  /// The fields as they are, compared with [_initialValues] to tell whether there are unsaved changes.
  Object get _values => (_userName, _email, _password, _canLogin, _canManageRepositories, _canChangeIdentity, _mustChangePassword);

  /// The fields as the page opened.
  late final Object _initialValues;

  bool get _dirty => _values != _initialValues;

  @override
  void initState() {
    super.initState();
    _initialValues = _values;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      final user = widget.user;
      final saved = user == null
          ? await ref.global.dispatchAsync(
              CreateUserAction(userName: _userName, email: _email, password: _password, mustChangePassword: _mustChangePassword),
            )
          : await ref.global.dispatchAsync(
              UpdateUserAction(
                id: user.id,
                userName: _userName,
                email: _email,
                canLogin: _canLogin,
                canManageRepositories: _canManageRepositories,
                canChangeIdentity: _canChangeIdentity,
                mustChangePassword: _mustChangePassword,
              ),
            );
      // The page stays open if it failed, so the input can be corrected.
      if (saved != null && mounted) {
        Navigator.pop(context, saved);
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final users = t.base.admin.users;
    final theme = Theme.of(context);
    final adminHint = users.editDialog.adminUnrestricted;
    return UnsavedChangesGuard(
      dirty: _dirty,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? users.editDialog.title : users.page.newUser),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else
              TextButton(
                key: const ValueKey('userForm.save'),
                onPressed: _save,
                child: Text(t.base.common.save),
              ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StringField(
                key: const ValueKey('userForm.userName'),
                value: _userName,
                label: t.base.user.userName,
                prefixIcon: const Icon(Icons.person),
                enabled: !_saving,
                autofocus: !_isEdit,
                textInputAction: TextInputAction.next,
                onChanged: (value) {
                  setState(() {
                    _userName = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              StringField(
                key: const ValueKey('userForm.email'),
                value: _email,
                label: t.base.user.emailOptional,
                prefixIcon: const Icon(Icons.email),
                keyboardType: TextInputType.emailAddress,
                enabled: !_saving,
                textInputAction: _isEdit ? TextInputAction.done : TextInputAction.next,
                onChanged: (value) {
                  setState(() {
                    _email = value;
                  });
                },
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 16),
                StringField(
                  key: const ValueKey('userForm.password'),
                  value: _password,
                  decoration: InputDecoration(
                    labelText: t.base.user.password,
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
                  enabled: !_saving,
                  textInputAction: TextInputAction.done,
                  onChanged: (value) {
                    setState(() {
                      _password = value;
                    });
                  },
                ),
              ],
              const SizedBox(height: 16),
              if (_isEdit) ...[
                SwitchListTile(
                  key: const ValueKey('userForm.canLogin'),
                  title: Text(users.editDialog.canLogin),
                  subtitle: Text(_isAdmin ? adminHint : users.editDialog.canLoginHint),
                  secondary: const Icon(Icons.login),
                  contentPadding: EdgeInsets.zero,
                  value: _canLogin,
                  onChanged: _saving || _isAdmin
                      ? null
                      : (value) {
                          setState(() {
                            _canLogin = value;
                          });
                        },
                ),
                SwitchListTile(
                  key: const ValueKey('userForm.canManageRepositories'),
                  title: Text(users.editDialog.canManageRepositories),
                  subtitle: Text(_isAdmin ? adminHint : users.editDialog.canManageRepositoriesHint),
                  secondary: const Icon(Icons.source),
                  contentPadding: EdgeInsets.zero,
                  value: _canManageRepositories,
                  onChanged: _saving || _isAdmin
                      ? null
                      : (value) {
                          setState(() {
                            _canManageRepositories = value;
                          });
                        },
                ),
                SwitchListTile(
                  key: const ValueKey('userForm.canChangeIdentity'),
                  title: Text(users.editDialog.canChangeIdentity),
                  subtitle: Text(_isAdmin ? adminHint : users.editDialog.canChangeIdentityHint),
                  secondary: const Icon(Icons.badge),
                  contentPadding: EdgeInsets.zero,
                  value: _canChangeIdentity,
                  onChanged: _saving || _isAdmin
                      ? null
                      : (value) {
                          setState(() {
                            _canChangeIdentity = value;
                          });
                        },
                ),
              ],
              SwitchListTile(
                key: const ValueKey('userForm.mustChangePassword'),
                title: Text(users.mustChangePassword),
                subtitle: Text(_isEdit ? users.editDialog.mustChangePasswordHint : users.chooseOwnPasswordHint),
                secondary: const Icon(Icons.lock_reset),
                contentPadding: EdgeInsets.zero,
                value: _mustChangePassword,
                onChanged: _saving
                    ? null
                    : (value) {
                        setState(() {
                          _mustChangePassword = value;
                        });
                      },
              ),
              if (_isEdit && _isAdmin) ...[
                const SizedBox(height: 16),
                Text(
                  t.flutter.admin.users.form.adminNote,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
