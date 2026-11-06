import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('McpSignInService');

/// The scheme the page on the loopback address sends the browser on to once it has the callback, which closes the
/// browser and brings the user back to the app.
const _appScheme = 'repolupe';

final mcpSignInProvider = Provider<McpSignInService>((ref) => const McpSignInService());

/// Signs in to MCP servers (OAuth) in the browser. The API (a server or the local instance) does the OAuth itself; the
/// app only takes the user to the authorization server and back. The authorization server redirects to a loopback
/// address (RFC 8252), since the MCP spec allows only `localhost` and `https` redirect URIs, and the app has no `https`
/// address of its own.
class McpSignInService {
  const McpSignInService();

  /// Calls [authorize] with the redirect URI to get the authorization URL, opens that, and returns the query
  /// parameters the authorization server sent the user back with: `code` and `state` (maybe `iss`), or `error` (maybe
  /// `error_description`). `null` if the user closed the browser before. Throws what [authorize] throws, and if the
  /// browser can't be opened.
  Future<Map<String, String>?> signIn(Future<String> Function(String redirectUri) authorize) async {
    final redirect = await LoopbackRedirect.start();
    try {
      final url = Uri.parse(await authorize(redirect.uri));
      // It comes from the MCP server, so only a web page is opened.
      if (!url.isScheme('https') && !url.isScheme('http')) {
        throw const FormatException('Unexpected authorization URL');
      }
      redirect.state = url.queryParameters['state'];
      try {
        await FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: _appScheme);
      } on PlatformException catch (e) {
        // Also when the browser didn't close itself after the redirect, and the user closed it.
        if (e.code != 'CANCELED') {
          rethrow;
        }
      }
      return redirect.callback;
    } finally {
      await redirect.close();
    }
  }
}

/// Receives the redirect of the authorization server on a loopback address, then sends the browser on to the app.
@visibleForTesting
class LoopbackRedirect {
  final HttpServer _ipv4;
  final HttpServer? _ipv6;

  /// The `state` of the sign-in. Only the callback with it is taken, since any page in the browser can send requests
  /// here.
  String? state;

  /// The query parameters of the callback, `null` until it arrives.
  Map<String, String>? callback;

  LoopbackRedirect._(this._ipv4, this._ipv6) {
    _ipv4.listen(_handle);
    _ipv6?.listen(_handle);
  }

  /// Listens on a free port of `127.0.0.1`, and on the same port of `::1` if the device has it, since browsers may
  /// resolve `localhost` to either.
  static Future<LoopbackRedirect> start() async {
    final ipv4 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    HttpServer? ipv6;
    try {
      ipv6 = await HttpServer.bind(InternetAddress.loopbackIPv6, ipv4.port, v6Only: true);
    } on SocketException catch (e) {
      _logger.fine('Not listening on ::1: $e');
    }
    return LoopbackRedirect._(ipv4, ipv6);
  }

  /// With `localhost`, as the MCP spec names it.
  String get uri => 'http://localhost:${_ipv4.port}/callback';

  Future<void> close() async {
    await _ipv4.close(force: true);
    await _ipv6?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final params = request.uri.queryParameters;
    final state = this.state;
    final ours = state != null && params['state'] == state;
    // Authorization servers may leave out the state of an error, which can only end the sign-in.
    final error = !params.containsKey('state') && params.containsKey('error');
    if (callback != null || request.method != 'GET' || request.uri.path != '/callback' || !(ours || error)) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    callback = params;
    response.statusCode = HttpStatus.found;
    response.headers.set(HttpHeaders.locationHeader, '$_appScheme://mcp-callback');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    await response.close();
  }
}
