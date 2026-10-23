import 'package:flutter/widgets.dart';

/// The languages the locale chooser offers (like the web's), as BCP 47 tags.
const suggestedLocales = [
  'en-US',
  'en-GB',
  'de-DE',
  'de-CH',
  'fr-FR',
  'es-ES',
  'it-IT',
  'nl-NL',
  'pt-BR',
  'pl-PL',
  'sv-SE',
  'tr-TR',
  'ru-RU',
  'ja-JP',
  'ko-KR',
  'zh-CN',
  'zh-TW',
  'vi-VN',
];

/// The names of [suggestedLocales] in English. Chinese is named by its script, which tells the two apart better than
/// the region.
const _names = {
  'en-US': 'English (United States)',
  'en-GB': 'English (United Kingdom)',
  'de-DE': 'German (Germany)',
  'de-CH': 'German (Switzerland)',
  'fr-FR': 'French (France)',
  'es-ES': 'Spanish (Spain)',
  'it-IT': 'Italian (Italy)',
  'nl-NL': 'Dutch (Netherlands)',
  'pt-BR': 'Portuguese (Brazil)',
  'pl-PL': 'Polish (Poland)',
  'sv-SE': 'Swedish (Sweden)',
  'tr-TR': 'Turkish (Türkiye)',
  'ru-RU': 'Russian (Russia)',
  'ja-JP': 'Japanese (Japan)',
  'ko-KR': 'Korean (South Korea)',
  'zh-CN': 'Chinese (Simplified)',
  'zh-TW': 'Chinese (Traditional)',
  'vi-VN': 'Vietnamese (Vietnam)',
};

/// The languages by their subtag in English, for the device's locales that [_names] does not know.
const _languages = {
  'en': 'English',
  'de': 'German',
  'fr': 'French',
  'es': 'Spanish',
  'it': 'Italian',
  'nl': 'Dutch',
  'pt': 'Portuguese',
  'pl': 'Polish',
  'sv': 'Swedish',
  'tr': 'Turkish',
  'ru': 'Russian',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
  'vi': 'Vietnamese',
};

/// The English name of the BCP 47 [tag], e.g. `German (Switzerland)` for `de-CH`, `null` if it is unknown.
String? localeName(String tag) {
  final name = _names[tag];
  if (name != null) {
    return name;
  }
  final subtags = tag.split('-');
  final language = _languages[subtags.first.toLowerCase()];
  if (language == null) {
    return null;
  }
  return subtags.length > 1 ? '$language (${subtags.last})' : language;
}

/// The device's language as a BCP 47 tag, e.g. `de-CH`, which the server uses for users without a locale.
String deviceLocaleTag() => WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();

/// The tags to offer: the device's languages first, since the user likely wants one of them, then
/// [suggestedLocales], without duplicates.
List<String> localeChoices() => {
  for (final locale in WidgetsBinding.instance.platformDispatcher.locales) locale.toLanguageTag(),
  ...suggestedLocales,
}.toList();
