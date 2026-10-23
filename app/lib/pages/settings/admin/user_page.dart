import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/user_form_page.dart';
import 'package:app/service/admin_user_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/admin/set_password_dialog.dart';
import 'package:app/widget/admin/user_flag_chips.dart';
import 'package:app/widget/delete_dialog.dart';
import 'package:app/widget/repositories/info_card.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// One user, for admins: who they are and what they may do, with editing them, setting their password (not the
/// admin's own, which the account page changes) and deleting them (not themselves, not admins). Pops once deleted.
class UserPage extends StatefulWidget {
  final UserDto user;

  const UserPage({super.key, required this.user});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> with Refena {
  late UserDto _user = widget.user;

  Future<void> _edit() async {
    final updated = await ref.global.dispatchAsync(NavigateAction.push<UserDto>(UserFormPage.edit(user: _user)));
    if (updated != null && mounted) {
      setState(() {
        _user = updated;
      });
    }
  }

  Future<void> _setPassword() async {
    final updated = await SetPasswordDialog.show(context, user: _user);
    if (updated != null && mounted) {
      setState(() {
        _user = updated;
      });
    }
  }

  Future<void> _delete() async {
    final dialog = context.t.base.admin.users.deleteDialog;
    final deleted = await DeleteDialog.show(
      context,
      title: dialog.title,
      text: '${dialog.intro} ${_user.userName}\n\n${dialog.consequences}',
      verify: _user.userName,
      keyPrefix: 'user.delete',
      onDelete: () => ref.global.dispatchAsync(DeleteUserAction(_user.id)),
    );
    if (deleted && mounted) {
      Navigator.pop(context);
    }
  }

  /// Why the user cannot be deleted, `null` if they can.
  String? _deleteBlockedReason(UserDto? me) {
    if (_user.id == me?.id) {
      return context.t.base.admin.users.page.cannotDeleteSelf;
    }
    if (_user.role == UserRole.admin) {
      return context.t.base.admin.users.page.cannotDeleteAdmin;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final t = context.t;
    final users = t.base.admin.users;
    final userPage = t.flutter.admin.users.userPage;
    final me = context.watch(meProvider);
    final isSelf = user.id == me?.id;
    final deleteBlockedReason = _deleteBlockedReason(me);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: Text(user.userName, overflow: TextOverflow.ellipsis)),
      body: ListView(
        key: const ValueKey('user.body'),
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          if (UserFlagChips.flags(user).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: UserFlagChips(user: user),
            ),
          InfoCard(
            icon: Icons.person_outline,
            title: users.page.user,
            actions: [
              TextButton.icon(
                key: const ValueKey('user.edit'),
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined),
                label: Text(t.base.common.edit),
              ),
            ],
            children: [
              InfoRow(label: t.base.user.userName, value: user.userName),
              InfoRow(label: t.base.user.email, value: user.email ?? '-'),
              if (user.fullName != null) InfoRow(label: t.base.settings.profile.fullName, value: user.fullName!),
              InfoRow(label: t.base.user.role, value: user.role == UserRole.admin ? t.base.user.roleAdmin : t.base.user.roleUser),
              InfoRow(label: t.base.settings.account.page.memberSince, value: formatDateTime(user.createdAt)),
              InfoRow(label: userPage.login, value: user.canLogin ? userPage.loginAllowed : userPage.loginDisabled),
              InfoRow(
                label: t.base.repositories.title,
                value: user.canManageRepositories ? userPage.repositoriesManage : userPage.repositoriesReadOnly,
              ),
              InfoRow(
                label: userPage.identity,
                value: user.canChangeIdentity ? userPage.identityEditable : userPage.identityFixed,
              ),
              InfoRow(
                label: t.base.user.password,
                value: user.mustChangePassword ? userPage.passwordMustChange : t.base.repositories.page.tokenSet,
              ),
            ],
          ),
          InfoCard(
            icon: Icons.key,
            title: t.base.user.password,
            actions: [
              FilledButton.tonalIcon(
                key: const ValueKey('user.setPassword'),
                onPressed: isSelf ? null : _setPassword,
                icon: const Icon(Icons.lock_reset),
                label: Text(users.page.setPassword),
              ),
            ],
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  isSelf ? users.page.cannotSetOwnPassword : users.passwordDialog.intro(name: user.userName),
                  style: muted,
                ),
              ),
            ],
          ),
          InfoCard(
            icon: Icons.delete_outline,
            title: t.base.common.delete,
            actions: [
              if (deleteBlockedReason == null)
                TextButton.icon(
                  key: const ValueKey('user.delete'),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(users.deleteDialog.title),
                ),
            ],
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  deleteBlockedReason ?? users.deleteDialog.consequences,
                  style: muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
