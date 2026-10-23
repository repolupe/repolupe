import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_user.dart';

/// A Repolupe server for the screenshots: answers a GET with the JSON of [routes] for its path (without the query),
/// and everything else with `NOT_FOUND`.
class ScreenshotServer {
  final HttpServer _server;
  final Map<String, Object?> routes;

  ScreenshotServer._(this._server, this.routes) {
    _server.listen(_handle);
  }

  /// Binds the server in the real async zone, so that it answers the requests sent outside the pumps.
  static Future<ScreenshotServer> start(WidgetTester tester, Map<String, Object?> routes) async {
    final server = (await tester.runAsync(() async {
      return ScreenshotServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), routes);
    }))!;
    addTearDown(() => server._server.close(force: true));
    return server;
  }

  String get apiUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> _handle(HttpRequest request) async {
    await request.drain<void>();
    final response = request.response;
    response.headers.contentType = ContentType.json;
    final path = request.uri.path;
    if (request.method == 'GET' && routes.containsKey(path)) {
      response.write(jsonEncode(routes[path]));
    } else {
      response.statusCode = 404;
      response.write(jsonEncode(fakeError('NOT_FOUND', 'Not found')));
    }
    await response.close();
  }
}
