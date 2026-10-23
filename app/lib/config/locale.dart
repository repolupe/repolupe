import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Shows the UI in the user's language (`UserDto.locale`), else in the device's. Dates and numbers are formatted with
/// that tag (e.g. `de-CH`), so they follow the texts around them, like the web.
Future<void> initLocale(RefenaContainer container) async {
  await initializeDateFormatting();

  // the device's language until the user is loaded
  await _apply(null);
  container.stream(meProvider).map((event) => event.next?.locale).distinct().asyncMap(_apply).listen(null);
}

Future<void> _apply(String? locale) async {
  final appLocale = locale != null ? await LocaleSettings.setLocaleRaw(locale) : await LocaleSettings.useDeviceLocale();
  _applyIntl(appLocale, locale);
}

/// Formats with the tag the texts are in, e.g. `de-CH`, else their language (e.g. `en` for `fr-FR`, which has no texts).
/// One without formats (e.g. `de-LI`) formats like its language.
void _applyIntl(AppLocale appLocale, String? locale) {
  final tags = locale != null ? [locale] : [for (final l in WidgetsBinding.instance.platformDispatcher.locales) l.toLanguageTag()];
  final tag = tags.where((t) => t.toLowerCase().split('-').first == appLocale.languageCode).firstOrNull ?? appLocale.languageTag;
  Intl.defaultLocale = Intl.verifiedLocale(
    tag,
    (l) => DateFormat.localeExists(l) && NumberFormat.localeExists(l),
    onFailure: (_) => appLocale.languageTag,
  );
}
