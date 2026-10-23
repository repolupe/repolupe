import 'package:app/gen/strings.g.dart';
import 'package:app/util/locales.dart';
import 'package:flutter/material.dart';

/// The language the model answers in (and of the interface, if it is translated): the device's ("Device default") or
/// one of [localeChoices].
class LocaleSheet extends StatelessWidget {
  /// The user's locale, `null` for the device's.
  final String? chosen;

  const LocaleSheet({super.key, required this.chosen});

  /// Returns the chosen locale (`locale` `null` for the device's), or `null` if the sheet was dismissed.
  static Future<({String? locale})?> show(BuildContext context, {required String? chosen}) {
    return showModalBottomSheet<({String? locale})>(
      context: context,
      showDragHandle: true,
      builder: (_) => LocaleSheet(chosen: chosen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final tags = localeChoices();

    void choose(String? locale) {
      Navigator.pop(context, (locale: locale));
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(t.base.settings.preferences.language, style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              t.base.settings.preferences.localeDialog.description,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  key: const ValueKey('preferences.locale.default'),
                  title: Text(t.flutter.settings.preferences.deviceDefault),
                  subtitle: Text(deviceLocaleTag()),
                  selected: chosen == null,
                  trailing: chosen == null ? const Icon(Icons.check) : null,
                  onTap: () => choose(null),
                ),
                for (final tag in tags)
                  ListTile(
                    key: ValueKey('preferences.locale.$tag'),
                    title: Text(switch (localeName(tag)) {
                      final name? => '$name – $tag',
                      null => tag,
                    }),
                    selected: tag == chosen,
                    trailing: tag == chosen ? const Icon(Icons.check) : null,
                    onTap: () => choose(tag),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
