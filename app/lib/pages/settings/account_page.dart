import 'package:app/gen/strings.g.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/settings/change_password_sheet.dart';
import 'package:app/widget/settings/email_sheet.dart';
import 'package:app/widget/settings/user_name_sheet.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The login details of the active account: user name and email (if the user may change them), role,
/// member since, and the password. The local instance has no email or password here, as the app logs in to it.
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
    final local = context.watch(accountProvider.select((state) => state.active?.isLocal ?? false));
    return Scaffold(
      appBar: AppBar(title: Text(t.base.settings.account.title)),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.paddingOf(context).bottom),
              children: [
                ListTile(
                  key: const ValueKey('account.userName'),
                  leading: const Icon(Icons.person),
                  title: Text(t.base.user.userName),
                  subtitle: Text(user.userName),
                  trailing: user.canChangeIdentity ? const Icon(Icons.edit) : null,
                  onTap: user.canChangeIdentity ? () => _editUserName(user, local: local) : null,
                ),
                if (!local && (user.email != null || user.canChangeIdentity))
                  ListTile(
                    key: const ValueKey('account.email'),
                    leading: const Icon(Icons.email),
                    title: Text(t.base.user.email),
                    subtitle: Text(user.email ?? '-'),
                    trailing: user.canChangeIdentity ? const Icon(Icons.edit) : null,
                    onTap: user.canChangeIdentity ? () => _editEmail(user) : null,
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
                if (!local)
                  ListTile(
                    key: const ValueKey('account.password'),
                    leading: const Icon(Icons.lock),
                    title: Text(t.base.user.password),
                    subtitle: const Text('●●●●●●'),
                    trailing: const Icon(Icons.edit),
                    onTap: () async {
                      await ChangePasswordSheet.show(context);
                    },
                  ),
              ],
            ),
    );
  }

  Future<void> _editUserName(UserDto user, {required bool local}) async {
    await UserNameSheet.show(context, userName: user.userName, email: user.email ?? '', showLoginHint: !local);
  }

  Future<void> _editEmail(UserDto user) async {
    await EmailSheet.show(context, userName: user.userName, email: user.email ?? '');
  }
}
