import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/account_page.dart';
import 'package:app/pages/settings/admin/config_page.dart';
import 'package:app/pages/settings/admin/extraction_page.dart';
import 'package:app/pages/settings/admin/llm_page.dart';
import 'package:app/pages/settings/admin/users_page.dart';
import 'package:app/pages/settings/preferences_page.dart';
import 'package:app/pages/settings/profile_page.dart';
import 'package:app/pages/settings/repositories_page.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/theme_mode_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/widget/theme_mode_sheet.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// A section of the settings: a tile of [SettingsPage] that opens its page.
class SettingsSection {
  /// The tile's key, `settings.<name>`.
  final String key;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget Function() page;

  const SettingsSection({
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
  });
}

/// The sections every user has. Repositories only for users who may manage them (the others only use the ones
/// shared with them in chats).
List<SettingsSection> _sections(Translations t, UserDto? user) => [
  if (user?.canManageRepositories ?? false)
    SettingsSection(
      key: 'settings.repositories',
      icon: Icons.source,
      title: t.base.repositories.title,
      subtitle: t.base.settings.page.repositoriesSubtitle,
      page: () => const RepositoriesPage(),
    ),
  SettingsSection(
    key: 'settings.account',
    icon: Icons.key,
    title: t.base.settings.account.title,
    subtitle: t.base.settings.page.accountSubtitle,
    page: () => const AccountPage(),
  ),
  SettingsSection(
    key: 'settings.profile',
    icon: Icons.badge,
    title: t.base.settings.profile.title,
    subtitle: t.base.settings.page.profileSubtitle,
    page: () => const ProfilePage(),
  ),
  SettingsSection(
    key: 'settings.preferences',
    icon: Icons.tune,
    title: t.base.settings.preferences.title,
    subtitle: t.base.settings.page.preferencesSubtitle,
    page: () => const PreferencesPage(),
  ),
];

/// The sections of admins. Users not on the local instance, whose admin is its only user.
List<SettingsSection> _adminSections(Translations t, {required bool local}) => [
  if (!local)
    SettingsSection(
      key: 'settings.admin.users',
      icon: Icons.group,
      title: t.base.admin.users.title,
      subtitle: t.base.settings.page.usersSubtitle,
      page: () => const UsersPage(),
    ),
  SettingsSection(
    key: 'settings.admin.llm',
    icon: Icons.smart_toy,
    title: t.base.admin.llm.title,
    subtitle: t.base.settings.page.llmSubtitle,
    page: () => const LlmPage(),
  ),
  SettingsSection(
    key: 'settings.admin.extraction',
    icon: Icons.file_copy,
    title: t.base.admin.extraction.title,
    subtitle: t.base.settings.page.extractionSubtitle,
    page: () => const ExtractionPage(),
  ),
  SettingsSection(
    key: 'settings.admin.config',
    icon: Icons.settings_applications,
    title: t.base.admin.config.title,
    subtitle: t.base.settings.page.configSubtitle,
    page: () => const ConfigPage(),
  ),
];

/// The hub of the settings: the theme of the device, the sections of the active account, the administration for
/// admins, and the logout.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final user = context.watch(meProvider);
    final theme = Theme.of(context);
    final themeMode = context.watch(themeModeProvider);
    final local = context.watch(accountProvider.select((state) => state.active?.isLocal ?? false));
    return Scaffold(
      appBar: AppBar(title: Text(t.base.settings.title)),
      body: ListView(
        key: const ValueKey('settings.sections'),
        padding: EdgeInsets.only(top: 8, bottom: 64 + MediaQuery.paddingOf(context).bottom),
        children: [
          ListTile(
            key: const ValueKey('settings.theme'),
            leading: Icon(themeMode.icon),
            title: Text(t.flutter.themeMode.title),
            subtitle: Text(themeMode.label(t)),
            onTap: () async {
              await ThemeModeSheet.show(context);
            },
          ),
          for (final section in _sections(t, user)) _SectionTile(section: section),
          if (user?.role == UserRole.admin) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(t.base.settings.page.admin, style: theme.textTheme.titleSmall),
            ),
            for (final section in _adminSections(t, local: local)) _SectionTile(section: section),
          ],
          const Divider(height: 24),
          ListTile(
            key: const ValueKey('settings.logout'),
            leading: const Icon(Icons.logout),
            title: Text(t.base.settings.page.logout),
            onTap: () async {
              await context.redux(accountProvider).dispatchAsync(LogoutAction());
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final SettingsSection section;

  const _SectionTile({required this.section});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey(section.key),
      leading: Icon(section.icon),
      title: Text(section.title),
      subtitle: Text(section.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await context.ref.global.dispatchAsync(NavigateAction.push(section.page()));
      },
    );
  }
}
