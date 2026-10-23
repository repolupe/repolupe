import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/settings/change_password_dialog.dart';
import 'package:app/widget/settings/identity_dialog.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The login details of the active account: user name and email (changed together, if the user may), role,
/// member since, and the password.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> with Refena {
  @override
  void initState() {
    super.initState();
    // Current when the page opens, e.g. after an admin changed the user.
    ensureRef((ref) {
      // ignore: discarded_futures
      ref.redux(meProvider).dispatchAsync(RefreshMeAction());
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final user = context.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.base.settings.account.title)),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  key: const ValueKey('account.userName'),
                  leading: const Icon(Icons.person),
                  title: Text(t.base.user.userName),
                  subtitle: Text(user.userName),
                  trailing: user.canChangeIdentity ? const Icon(Icons.edit) : null,
                  onTap: user.canChangeIdentity ? () => _editIdentity(user) : null,
                ),
                if (user.email != null || user.canChangeIdentity)
                  ListTile(
                    key: const ValueKey('account.email'),
                    leading: const Icon(Icons.email),
                    title: Text(t.base.user.email),
                    subtitle: Text(user.email ?? '-'),
                    trailing: user.canChangeIdentity ? const Icon(Icons.edit) : null,
                    onTap: user.canChangeIdentity ? () => _editIdentity(user) : null,
                  ),
                ListTile(
                  leading: const Icon(Icons.shield),
                  title: Text(t.base.user.role),
                  subtitle: Text(user.role == UserRole.admin ? t.base.user.roleAdmin : t.base.user.roleUser),
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text(t.base.settings.account.page.memberSince),
                  subtitle: Text(formatDateTime(user.createdAt)),
                ),
                ListTile(
                  key: const ValueKey('account.password'),
                  leading: const Icon(Icons.lock),
                  title: Text(t.base.user.password),
                  subtitle: const Text('●●●●●●'),
                  trailing: const Icon(Icons.edit),
                  onTap: () async {
                    await ChangePasswordDialog.show(context);
                  },
                ),
              ],
            ),
    );
  }

  Future<void> _editIdentity(UserDto user) async {
    await IdentityDialog.show(context, userName: user.userName, email: user.email ?? '');
  }
}
