/// Turns the server address the user typed into its origin, e.g. `repolupe.example.com/`
/// into `https://repolupe.example.com`. Returns `null` if it is not an http(s) URL.
String? normalizeApiUrl(String input) {
  var url = input.trim();
  if (!url.contains('://')) {
    url = 'https://$url';
  }

  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
    return null;
  }

  // Keep a path, in case the server runs behind a reverse proxy under one.
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}
