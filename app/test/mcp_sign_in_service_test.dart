import 'dart:io';

import 'package:app/service/mcp_sign_in_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_auth_2_platform_interface/flutter_web_auth_2_platform_interface.dart';

/// Sends a GET to [url] like a browser would, without following redirects, and returns the status and `Location`.
Future<(int, String?)> _get(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>();
    return (response.statusCode, response.headers.value(HttpHeaders.locationHeader));
  } finally {
    client.close(force: true);
  }
}

/// A browser in which the user signs in right away: the authorization server sends them back to the redirect URI with
/// [callback] (none if `null`), whose page sends the browser on to the app. With [close], the user closes the browser
/// instead (after the redirect, if there is one).
class _FakeBrowser extends FlutterWebAuth2Platform {
  Map<String, String>? callback;
  bool close = false;

  /// The URLs it opened.
  final opened = <String>[];

  /// The answers of the redirect URI.
  final redirects = <(int, String?)>[];

  @override
  Future<String> authenticate({required String url, required String callbackUrlScheme, required Map<String, dynamic> options}) async {
    opened.add(url);
    expect(callbackUrlScheme, 'repolupe');
    String? location;
    if (callback case final callback?) {
      final redirectUri = Uri.parse(Uri.parse(url).queryParameters['redirect_uri']!);
      final response = await _get(redirectUri.replace(queryParameters: callback));
      redirects.add(response);
      location = response.$2;
    }
    if (close || location == null || !location.startsWith('$callbackUrlScheme:')) {
      throw PlatformException(code: 'CANCELED');
    }
    return location;
  }

  @override
  Future<void> clearAllDanglingCalls() async {}
}

/// The authorization server's URL for [redirectUri], which comes from the API.
String _authorizationUrl(String redirectUri) => Uri.https('auth.example.com', '/authorize', {
  'client_id': 'client-1',
  'redirect_uri': redirectUri,
  'state': 'state-1',
}).toString();

void main() {
  late _FakeBrowser browser;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The binding answers every request with 400, but these go to the loopback address of the sign-in.
    HttpOverrides.global = null;
  });

  setUp(() {
    browser = _FakeBrowser();
    FlutterWebAuth2Platform.instance = browser;
  });

  /// Signs in with the authorization URL of [_authorizationUrl], recording the redirect URI.
  Future<Map<String, String>?> signIn(List<String> redirectUris) => const McpSignInService().signIn((redirectUri) async {
    redirectUris.add(redirectUri);
    return _authorizationUrl(redirectUri);
  });

  test('returns what the authorization server sent back, and sends the browser on to the app', () async {
    browser.callback = {'state': 'state-1', 'code': 'code-1', 'iss': 'https://auth.example.com'};
    final redirectUris = <String>[];

    final callback = await signIn(redirectUris);

    expect(callback, {'state': 'state-1', 'code': 'code-1', 'iss': 'https://auth.example.com'});
    expect(redirectUris.single, matches(RegExp(r'^http://localhost:\d+/callback$')));
    expect(browser.opened, [_authorizationUrl(redirectUris.single)]);
    expect(browser.redirects, [(HttpStatus.found, 'repolupe://mcp-callback')]);
    // No longer listening.
    await expectLater(_get(Uri.parse(redirectUris.single)), throwsA(isA<SocketException>()));
  });

  test('returns the callback also if the user closes the browser after it', () async {
    browser
      ..callback = {'state': 'state-1', 'code': 'code-1'}
      ..close = true;

    expect(await signIn([]), {'state': 'state-1', 'code': 'code-1'});
  });

  test('returns an error the authorization server sent back without the state', () async {
    browser.callback = {'error': 'access_denied'};

    expect(await signIn([]), {'error': 'access_denied'});
  });

  test('returns null if the user closes the browser before the callback', () async {
    expect(await signIn([]), isNull);
    expect(browser.opened, hasLength(1));
  });

  test('ignores a callback of another sign-in', () async {
    browser.callback = {'state': 'state-2', 'code': 'code-2'};

    expect(await signIn([]), isNull);
    expect(browser.redirects, [(HttpStatus.notFound, null)]);
  });

  test('opens only a web page, and stops listening if starting the sign-in fails', () async {
    final redirectUris = <String>[];
    final script = const McpSignInService().signIn((redirectUri) async {
      redirectUris.add(redirectUri);
      return 'javascript:alert(1)';
    });
    await expectLater(script, throwsFormatException);
    expect(browser.opened, isEmpty);
    await expectLater(_get(Uri.parse(redirectUris.single)), throwsA(isA<SocketException>()));

    final failing = const McpSignInService().signIn((_) async => throw StateError('unreachable'));
    await expectLater(failing, throwsStateError);
    expect(browser.opened, isEmpty);
  });

  test('the loopback address takes only the first callback with the state of the sign-in', () async {
    final redirect = await LoopbackRedirect.start();
    addTearDown(redirect.close);
    redirect.state = 'state-1';
    final url = Uri.parse(redirect.uri);
    Future<(int, String?)> get(String path, Map<String, String> query) => _get(url.replace(path: path, queryParameters: query));

    expect(await get('/callback', {'state': 'state-2', 'code': 'code-2'}), (HttpStatus.notFound, null));
    expect(await get('/other', {'state': 'state-1', 'code': 'code-1'}), (HttpStatus.notFound, null));
    // Also on 127.0.0.1, since `localhost` may resolve to ::1.
    expect(await _get(url.replace(host: '127.0.0.1', queryParameters: {'code': 'code-1'})), (HttpStatus.notFound, null));
    expect(redirect.callback, isNull);

    expect(await get('/callback', {'state': 'state-1', 'code': 'code-1'}), (HttpStatus.found, 'repolupe://mcp-callback'));
    expect(await get('/callback', {'state': 'state-1', 'code': 'code-3'}), (HttpStatus.notFound, null));
    expect(redirect.callback, {'state': 'state-1', 'code': 'code-1'});
  });
}
