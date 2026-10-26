import 'package:app/gen/strings.g.dart';
import 'package:app/service/theme_mode_service.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Lets the user choose between the system's, the light and the dark theme.
class ThemeModeSheet extends StatelessWidget {
  const ThemeModeSheet();

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => const ThemeModeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final current = context.watch(themeModeProvider);
    // The sheet's context is gone once it is closed.
    final ref = context.ref;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in ThemeMode.values)
            ListTile(
              key: ValueKey('theme.${mode.name}'),
              leading: Icon(mode.icon),
              title: Text(mode.label(t)),
              trailing: mode == current ? const Icon(Icons.check) : null,
              selected: mode == current,
              onTap: () async {
                Navigator.pop(context);
                await ref.redux(themeModeProvider).dispatchAsync(SetThemeModeAction(mode));
              },
            ),
        ],
      ),
    );
  }
}

extension ThemeModeLabel on ThemeMode {
  String label(Translations t) => switch (this) {
    ThemeMode.system => t.base.settings.themeMode.system,
    ThemeMode.light => t.base.settings.themeMode.light,
    ThemeMode.dark => t.base.settings.themeMode.dark,
  };

  IconData get icon => switch (this) {
    ThemeMode.system => Icons.brightness_auto,
    ThemeMode.light => Icons.light_mode,
    ThemeMode.dark => Icons.dark_mode,
  };
}
