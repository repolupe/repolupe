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
import 'package:app/service/api_service.dart';
import 'package:app/service/instance_name_provider.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/theme_mode_service.dart';
import 'package:app/service/version_provider.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/locales.dart';
import 'package:app/widget/account_sheet.dart';
import 'package:app/widget/app_logo.dart';
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

  /// The current state of the page, e.g. the number of repositories. `null` shows none.
  final String? subtitle;
  final Widget Function() page;

  const SettingsSection({
    required this.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.page,
  });
}

/// The sections every user has, with their state. Repositories only for users who may manage them (the others only
/// use the ones shared with them in chats). [repositoryCount] and [models] are `null` until they are loaded.
List<SettingsSection> _sections(Translations t, UserDto? user, {required int? repositoryCount, required List<ModelDto>? models}) => [
  if (user?.canManageRepositories ?? false)
    SettingsSection(
      key: 'settings.repositories',
      icon: Icons.source,
      title: t.base.repositories.title,
      subtitle: repositoryCount != null ? t.base.settings.page.repositoryCount(count: repositoryCount) : null,
      page: () => const RepositoriesPage(),
    ),
  SettingsSection(
    key: 'settings.account',
    icon: Icons.key,
    title: t.base.settings.account.title,
    subtitle: user != null ? [user.userName, ?user.email].join(' · ') : null,
    page: () => const AccountPage(),
  ),
  SettingsSection(
    key: 'settings.profile',
    icon: Icons.badge,
    title: t.base.settings.profile.title,
    subtitle: user != null ? user.fullName ?? user.firstName ?? user.about ?? t.base.settings.page.profileEmpty : null,
    page: () => const ProfilePage(),
  ),
  SettingsSection(
    key: 'settings.preferences',
    icon: Icons.tune,
    title: t.base.settings.preferences.title,
    subtitle: user != null
        // The server uses the device's language for users without one.
        ? [?_modelName(user, models), user.locale ?? deviceLocaleTag()].join(' · ')
        : null,
    page: () => const PreferencesPage(),
  ),
];

/// The model the user's chats use: their own, else the default one. `null` if there is none, or until the [models]
/// are loaded.
String? _modelName(UserDto user, List<ModelDto>? models) {
  final chosen = models?.where((m) => m.id == user.defaultModelId).firstOrNull ?? models?.where((m) => m.isDefault).firstOrNull;
  return chosen?.displayName;
}

/// The sections of admins. Users not on the local instance, whose admin is its only user.
List<SettingsSection> _adminSections(Translations t, {required bool local}) => [
  if (!local)
    SettingsSection(
      key: 'settings.admin.users',
      icon: Icons.group,
      title: t.base.admin.users.title,
      page: () => const UsersPage(),
    ),
  SettingsSection(
    key: 'settings.admin.llm',
    icon: Icons.smart_toy,
    title: t.base.admin.llm.title,
    page: () => const LlmPage(),
  ),
  SettingsSection(
    key: 'settings.admin.extraction',
    icon: Icons.file_copy,
    title: t.base.admin.extraction.title,
    page: () => const ExtractionPage(),
  ),
  SettingsSection(
    key: 'settings.admin.config',
    icon: Icons.settings_applications,
    title: t.base.admin.config.title,
    page: () => const ConfigPage(),
  ),
];

/// The hub of the settings: the active account of the device, which opens a sheet to change it, then the groups App
/// (the theme of the device), User (the sections of the active account, with their state) and Admin (the
/// administration, for admins), and at the bottom the logo with the app's version.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with Refena {
  /// For the states of the sections, `null` until loaded (or if loading failed, then the state is left out).
  int? _repositoryCount;
  List<ModelDto>? _models;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      // ignore: discarded_futures
      _load();
    });
  }

  /// Loads what the states need beyond the user. They are only a summary, so a failed request shows no error.
  Future<void> _load() async {
    final api = ref.redux(apiProvider);
    final canManageRepositories = ref.read(meProvider)?.canManageRepositories ?? false;
    final (repositories, models) = await (
      canManageRepositories ? _loadOrNull(() => api.dispatchAsyncTakeResult(ApiListRepositoriesAction())) : Future.value(),
      _loadOrNull(() => api.dispatchAsyncTakeResult(ApiListModelsAction())),
    ).wait;
    if (mounted) {
      setState(() {
        _repositoryCount = repositories?.length;
        _models = models;
      });
    }
  }

  Future<T?> _loadOrNull<T>(Future<T> Function() load) async {
    try {
      return await load();
    } on ClientError {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final user = context.watch(meProvider);
    final themeMode = context.watch(themeModeProvider);
    final local = context.watch(accountProvider.select((state) => state.active?.isLocal ?? false));
    return Scaffold(
      appBar: AppBar(title: Text(t.base.settings.title)),
      body: ListView(
        key: const ValueKey('settings.sections'),
        padding: EdgeInsets.only(top: 24, bottom: 64 + MediaQuery.paddingOf(context).bottom),
        children: [
          const _AccountChip(),
          _GroupHeader(title: t.base.settings.page.app),
          ListTile(
            key: const ValueKey('settings.theme'),
            leading: Icon(themeMode.icon),
            title: Text(t.base.settings.themeMode.title),
            subtitle: Text(themeMode.label(t)),
            onTap: () async {
              await ThemeModeSheet.show(context);
            },
          ),
          _GroupHeader(title: t.base.settings.page.user),
          for (final section in _sections(t, user, repositoryCount: _repositoryCount, models: _models))
            // The page may have changed the state, e.g. added a repository.
            _SectionTile(section: section, onReturn: _load),
          if (user?.role == UserRole.admin) ...[
            _GroupHeader(title: t.base.settings.page.admin),
            for (final section in _adminSections(t, local: local)) _SectionTile(section: section, onReturn: _load),
          ],
          const _AppInfo(),
        ],
      ),
    );
  }
}

/// The active account, which opens a sheet to change it. The local instance is shown as `This device` only, its
/// single user's name (`admin`) tells nothing.
class _AccountChip extends StatelessWidget {
  const _AccountChip();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final account = context.watch(accountProvider.select((state) => state.active));
    // As of the login until the user is loaded.
    final userName = context.watch(meProvider.select((user) => user?.userName)) ?? account?.user.userName;
    final local = account?.isLocal ?? false;
    final label = switch (account) {
      null => t.flutter.settings.accountSheet.accounts,
      _ when local => account.server,
      _ => '${userName ?? account.user.userName} · ${account.server}',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Center(
        child: ActionChip(
          key: const ValueKey('settings.accounts'),
          avatar: const Icon(Icons.account_circle),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          onPressed: () async {
            await AccountSheet.show(context);
          },
        ),
      ),
    );
  }
}

/// The logo, the product name and the app's version (left out until loaded).
class _AppInfo extends StatelessWidget {
  const _AppInfo();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final version = context.watch(versionProvider).data;
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        key: const ValueKey('settings.appInfo'),
        children: [
          const AppLogo(size: 64),
          const SizedBox(height: 8),
          Text(productName, style: textTheme.titleMedium?.copyWith(color: color)),
          if (version != null)
            Text(
              t.flutter.settings.page.version(version: version),
              style: textTheme.bodySmall?.copyWith(color: color),
            ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;

  const _GroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final SettingsSection section;

  /// Called when its page was closed.
  final Future<void> Function() onReturn;

  const _SectionTile({required this.section, required this.onReturn});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey(section.key),
      leading: Icon(section.icon),
      title: Text(section.title),
      subtitle: switch (section.subtitle) {
        final subtitle? => Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        null => null,
      },
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await context.ref.global.dispatchAsync(NavigateAction.push(section.page()));
        await onReturn();
      },
    );
  }
}
