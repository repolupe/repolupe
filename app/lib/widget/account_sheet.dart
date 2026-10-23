import 'package:app/gen/strings.g.dart';
import 'package:app/pages/setup_page.dart';
import 'package:app/service/account_service.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Lists the accounts to switch between, adds one, or logs out of the active one.
class AccountSheet extends StatelessWidget {
  const AccountSheet();

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => const AccountSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final state = context.watch(accountProvider);
    // The sheet's context is gone once it is closed.
    final ref = context.ref;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final account in state.accounts)
            ListTile(
              leading: Icon(account.key == state.activeKey ? Icons.check_circle : Icons.account_circle_outlined),
              title: Text(account.user.userName),
              subtitle: Text(account.server),
              selected: account.key == state.activeKey,
              onTap: () async {
                Navigator.pop(context);
                if (account.key != state.activeKey) {
                  await ref.redux(accountProvider).dispatchAsync(SwitchAccountAction(account));
                }
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(t.flutter.settings.accountSheet.addAccount),
            onTap: () async {
              Navigator.pop(context);
              await ref.global.dispatchAsync(NavigateAction.push(const SetupPage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(t.base.settings.page.logout),
            onTap: () async {
              Navigator.pop(context);
              await ref.redux(accountProvider).dispatchAsync(LogoutAction());
            },
          ),
        ],
      ),
    );
  }
}
