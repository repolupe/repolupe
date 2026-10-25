import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/widget/settings/profile_dialog.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The profile of the active account, which the assistant is told about the user: full name, first name and
/// about, edited together in [ProfileDialog].
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with Refena {
  @override
  void initState() {
    super.initState();
    // Current when the page opens, e.g. after it was edited on another device.
    ensureRef((ref) {
      // ignore: discarded_futures
      ref.redux(meProvider).dispatchAsync(RefreshMeAction());
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final user = context.watch(meProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.base.settings.profile.title)),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.paddingOf(context).bottom),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    t.base.settings.profile.page.description,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  key: const ValueKey('profile.fullName'),
                  leading: const Icon(Icons.person),
                  title: Text(t.base.settings.profile.fullName),
                  subtitle: Text(user.fullName ?? '-'),
                  trailing: const Icon(Icons.edit),
                  onTap: () => _edit(user),
                ),
                ListTile(
                  key: const ValueKey('profile.firstName'),
                  leading: const Icon(Icons.person_outline),
                  title: Text(t.base.settings.profile.firstName),
                  subtitle: Text(user.firstName ?? '-'),
                  trailing: const Icon(Icons.edit),
                  onTap: () => _edit(user),
                ),
                ListTile(
                  key: const ValueKey('profile.about'),
                  leading: const Icon(Icons.info_outline),
                  title: Text(t.base.settings.profile.about),
                  subtitle: Text(user.about ?? '-'),
                  trailing: const Icon(Icons.edit),
                  onTap: () => _edit(user),
                ),
              ],
            ),
    );
  }

  Future<void> _edit(UserDto user) async {
    await ProfileDialog.show(
      context,
      fullName: user.fullName ?? '',
      firstName: user.firstName ?? '',
      about: user.about ?? '',
    );
  }
}
