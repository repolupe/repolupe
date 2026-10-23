import 'dart:convert';
import 'dart:io';

/// Copies the web's texts (vue-i18n, `web/i18n/locales/<code>.json`) into the app's `base` namespace (slang,
/// `assets/i18n/<code>/base.json`), so both show the same texts. Plurals are converted the way vue-i18n picks them:
/// `a | b` becomes `{one: a, other: b}` and `a | b | c` becomes `{zero: a, one: b, other: c}`.
///
/// Run from app/: `fvm dart tool/import_web_i18n.dart && fvm dart run slang` (not `dart run`, which first builds the
/// native assets).
void main() {
  final app = File.fromUri(Platform.script).parent.parent;
  final web = Directory('${app.path}/../web/i18n/locales');
  final files = web.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final code = file.uri.pathSegments.last.replaceAll('.json', '');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final target = File('${app.path}/assets/i18n/$code/base.json')..createSync(recursive: true);
    target.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(_convert(json, ''))}\n');
    // ignore: avoid_print
    print('$code: ${file.path} -> ${target.path}');
  }
}

Object _convert(Object? node, String path) {
  return switch (node) {
    Map<String, dynamic>() => {for (final MapEntry(:key, :value) in node.entries) key: _convert(value, '$path$key.')},
    String() => _convertText(node, path.substring(0, path.length - 1)),
    _ => throw FormatException('$path: unexpected value $node'),
  };
}

Object _convertText(String text, String key) {
  // vue-i18n's literal syntax, e.g. {'|'} for a literal pipe, has no counterpart in slang
  if (text.contains("{'")) {
    throw FormatException('$key: literal interpolation is not supported: $text');
  }
  final forms = text.split('|').map((f) => f.trim()).toList();
  return switch (forms) {
    [_] => text,
    [final one, final other] => {'one': one, 'other': other},
    [final zero, final one, final other] => {'zero': zero, 'one': one, 'other': other},
    _ => throw FormatException('$key: ${forms.length} plural forms are not supported: $text'),
  };
}
