import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/user_form_page.dart';
import 'package:app/pages/settings/admin/user_page.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/widget/admin/user_flag_chips.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Every user of the server, for admins, with a search, each opening its page, and a button to create one.
/// The local instance has only its admin, so it offers no button but says so.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> with Refena {
  /// `null` until they are loaded.
  List<UserDto>? _users;
  bool _loading = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      // ignore: discarded_futures
      _load();
    });
  }

  /// Loads the users; [quiet] without the progress indicator (after a change, when the list is shown already).
  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final users = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiListUsersAction());
      if (mounted) {
        setState(() {
          _users = users;
        });
      }
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.users.page.loadFailed(error: e.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// Opens the form; the list is loaded again with the new user.
  Future<void> _create() async {
    final created = await ref.global.dispatchAsync(NavigateAction.push<UserDto>(const UserFormPage.create()));
    if (created != null && mounted) {
      await _load(quiet: true);
    }
  }

  /// Opens the user's page; the list is loaded again when it closes (the user may have been changed or deleted).
  Future<void> _open(UserDto user) async {
    await ref.global.dispatchAsync(NavigateAction.push(UserPage(user: user)));
    if (mounted) {
      await _load(quiet: true);
    }
  }

  List<UserDto> _filtered(List<UserDto> users) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return users;
    }
    return users
        .where(
          (u) =>
              u.userName.toLowerCase().contains(query) ||
              (u.email?.toLowerCase().contains(query) ?? false) ||
              (u.fullName?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    final t = context.t;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final local = context.watch(accountProvider.select((state) => state.active?.isLocal ?? false));
    return Scaffold(
      appBar: AppBar(title: Text(t.base.admin.users.title)),
      floatingActionButton: users == null || local
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('users.new'),
              onPressed: _create,
              icon: const Icon(Icons.person_add),
              label: Text(t.base.admin.users.page.newUser),
            ),
      body: users == null
          ? _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonalIcon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(t.base.common.retry),
                    ),
                  )
          : ListView(
              key: const ValueKey('users.list'),
              padding: EdgeInsets.only(bottom: (local ? 16 : 88) + MediaQuery.paddingOf(context).bottom),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(t.base.admin.users.page.count(count: users.length), style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    local ? t.flutter.admin.users.page.localOnly : t.base.admin.users.page.description,
                    style: muted,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    key: const ValueKey('users.search'),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: t.base.common.search,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                  ),
                ),
                for (final user in _filtered(users)) _UserTile(user: user, onTap: () => _open(user)),
                if (_filtered(users).isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      users.isEmpty ? t.base.admin.users.page.noUsers : t.flutter.admin.users.page.noMatch,
                      style: muted,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// A user: their user name, email and full name, and what sets them apart (the admin role, restrictions).
class _UserTile extends StatelessWidget {
  final UserDto user;
  final VoidCallback onTap;

  const _UserTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final email = user.email;
    final fullName = user.fullName;
    final flags = UserFlagChips.flags(user);
    return ListTile(
      key: ValueKey('users.${user.id}'),
      leading: Icon(user.role == UserRole.admin ? Icons.shield_outlined : Icons.person_outline),
      title: Text(user.userName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: email == null && fullName == null && flags.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (email != null) Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (fullName != null) Text(fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (flags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: UserFlagChips(user: user),
                  ),
              ],
            ),
      isThreeLine: [email, fullName].nonNulls.length + (flags.isEmpty ? 0 : 1) > 1,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
