import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/settings/admin/server_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/fake_user.dart';
import 'support/persistence.dart';
import 'support/rust.dart';

const _adminId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';

/// Pumps until [finder] finds something, letting the requests to the server run meanwhile.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

/// The subtitle of the tile with [key], `null` if it has none or no text.
String? _subtitle(WidgetTester tester, String key) {
  final subtitle = tester.widget<ListTile>(find.byKey(ValueKey(key))).subtitle;
  return subtitle is Text ? subtitle.data : null;
}

/// Opens the page for the admin of a server answering `GET /api/v1/me` and `/server` (version `1.2.3`). With [local],
/// the active account is the local instance's, while the requests still go to the server. Returns the texts copied to
/// the clipboard.
Future<List<String>> _pumpPage(WidgetTester tester, {required bool local}) async {
  // Bound and listened to in the real async zone, so that it also answers the requests sent outside the pumps.
  final server = (await tester.runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0)))!;
  addTearDown(() => server.close(force: true));
  await tester.runAsync(() async {
    server.listen((request) async {
      final response = request.response;
      response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/v1/me') {
        response.write(jsonEncode(fakeUser(id: _adminId, userName: 'admin', role: 'ADMIN')));
      } else if (request.uri.path == '/api/v1/server') {
        response.write(jsonEncode({'version': '1.2.3'}));
      } else {
        response.statusCode = 404;
        response.write(jsonEncode(fakeError('NOT_FOUND', 'Not found')));
      }
      await response.close();
    });
  });

  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map<Object?, Object?>)['text']! as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

  final account = Account(
    apiUrl: 'http://127.0.0.1:${server.port}',
    token: 'session-token',
    user: AccountUser(id: _adminId, userName: 'admin'),
  );
  final stored = local ? account.copyWith(apiUrl: null) : account;
  final persistence = (await tester.runAsync(() => mockPersistence(account: stored)))!;
  final container = RefenaContainer(overrides: [persistenceProvider.overrideWithValue(persistence)]);
  container.redux(apiProvider).dispatch(ApiSetAccountAction(account));
  await tester.runAsync(() => container.redux(meProvider).dispatchAsync(RefreshMeAction()));

  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          navigatorKey: container.read(navigationProvider).key,
          scaffoldMessengerKey: container.read(snackBarProvider).key,
          home: const ServerPage(),
        ),
      ),
    ),
  );
  await _pumpUntil(tester, find.text('1.2.3'));
  return copied;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the server page shows the base URL and the version, tapping copies them', (tester) async {
    final copied = await _pumpPage(tester, local: false);
    final baseUrl = _subtitle(tester, 'server.baseUrl')!;
    expect(baseUrl, matches(RegExp(r'^http://127\.0\.0\.1:\d+$')));
    expect(_subtitle(tester, 'server.version'), '1.2.3');

    await tester.tap(find.byKey(const ValueKey('server.baseUrl')));
    await tester.pump();
    expect(find.text('Copied to the clipboard.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('server.version')));
    await tester.pump();
    expect(copied, [baseUrl, '1.2.3']);
  });

  testWidgets('the local instance has no base URL to copy', (tester) async {
    final copied = await _pumpPage(tester, local: true);
    expect(_subtitle(tester, 'server.baseUrl'), 'This device');

    await tester.tap(find.byKey(const ValueKey('server.baseUrl')));
    await tester.pump();
    expect(copied, isEmpty);
  });
}
