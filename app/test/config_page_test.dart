import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/settings/admin/config_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/instance_name_provider.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/fake_admin.dart';
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

/// Pumps until the requests of the page are done (no progress indicator any more) and its animations have settled.
Future<void> _settle(WidgetTester tester) async {
  final progress = find.byType(CircularProgressIndicator);
  for (var i = 0; i < 100 && progress.evaluate().isNotEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  expect(progress, findsNothing);
  await tester.pumpAndSettle();
}

/// A server with an admin and the config, whose overrides `POST /api/v1/config` replaces (rejecting
/// [rejectedValue] with a message); the POSTs are recorded by their path with their body.
class _FakeServer {
  final HttpServer server;
  List<Map<String, dynamic>> entries;
  String? rejectedValue;
  final requests = <(String, Map<String, dynamic>?)>[];
  int instances = 0;

  _FakeServer(this.server, {required this.entries}) {
    server.listen(_handle);
  }

  static Future<_FakeServer> start(WidgetTester tester, {required List<Map<String, dynamic>> entries}) async {
    final fake = (await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      return _FakeServer(server, entries: entries);
    }))!;
    addTearDown(() => fake.server.close(force: true));
    return fake;
  }

  String get apiUrl => 'http://127.0.0.1:${server.port}';

  String get instanceName {
    final entry = entries.firstWhere((e) => e['key'] == 'INSTANCE_NAME');
    return (entry['override'] ?? entry['env']) as String;
  }

  Future<void> _handle(HttpRequest request) async {
    final bodyText = await utf8.decodeStream(request);
    final body = request.method == 'POST' && bodyText.isNotEmpty ? jsonDecode(bodyText) as Map<String, dynamic> : null;
    final response = request.response;
    response.headers.contentType = ContentType.json;
    if (request.method == 'POST') {
      requests.add((request.uri.path, body));
    }
    switch ((request.method, request.uri.path)) {
      case ('GET', '/api/v1/me'):
        response.write(jsonEncode(fakeUser(id: _adminId, userName: 'alice', role: 'ADMIN')));
      case ('GET', '/api/v1/instance'):
        instances++;
        response.write(jsonEncode({'name': instanceName}));
      case ('GET', '/api/v1/config'):
        response.write(jsonEncode(entries));
      case ('POST', '/api/v1/config'):
        if (body!.values.contains(rejectedValue)) {
          response.statusCode = 400;
          response.write(jsonEncode(fakeError('BAD_REQUEST', 'OCR_SCAN_CONFIDENCE: expected a number between 0 and 1')));
        } else {
          entries = [
            for (final entry in entries) {...entry, 'override': body[entry['key']]},
          ];
          response.write(jsonEncode(entries));
        }
      default:
        response.statusCode = 404;
        response.write(jsonEncode(fakeError('NOT_FOUND', 'Not found')));
    }
    await response.close();
  }
}

/// Opens the page for the admin of [server], whose user is loaded.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeServer server) async {
  tester.view.physicalSize = const Size(600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final account = Account(
    apiUrl: server.apiUrl,
    token: 'session-token',
    user: AccountUser(id: _adminId, userName: 'alice'),
  );
  final persistence = (await tester.runAsync(() => mockPersistence(account: account)))!;
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
          home: const ConfigPage(),
        ),
      ),
    ),
  );
  // The page loads after its first frame, so its progress indicator shows only then.
  await tester.pump();
  await tester.pump();
  await _settle(tester);
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the config page lists the settings, sets and removes an override with the whole map, and keeps the dialog open on an error', (
    tester,
  ) async {
    final server = await _FakeServer.start(
      tester,
      entries: [
        fakeConfigEntry(key: 'ADMIN_PASSWORD', env: '******'),
        fakeConfigEntry(key: 'INSTANCE_NAME', env: 'Repolupe', runtime: true),
        fakeConfigEntry(key: 'OCR_ENGINE', env: 'paddle', override: 'none', runtime: true),
        fakeConfigEntry(key: 'OCR_SCAN_CONFIDENCE', env: '0.5', runtime: true),
        fakeConfigEntry(key: 'REPOS_DIR'),
      ],
    );
    final container = await _pumpPage(tester, server);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();
    // The start page shows the instance name, which an override changes.
    expect(await tester.runAsync(() => container.future(instanceNameProvider)), 'Repolupe');

    // The rows: the env values (the secret masked, an unset one as "Not set"), the override, and the runtime marker.
    expect(find.text('ADMIN_PASSWORD'), findsOneWidget);
    expect(find.text('Env: ******', findRichText: true), findsOneWidget);
    expect(find.text('Env: Repolupe', findRichText: true), findsOneWidget);
    expect(find.text('Env: paddle', findRichText: true), findsOneWidget);
    expect(find.text('Override: none', findRichText: true), findsOneWidget);
    expect(find.text('Env: not set', findRichText: true), findsOneWidget);
    expect(find.text('Runtime'), findsNWidgets(3));
    // Only runtime settings open the dialog.
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('config.entry.REPOS_DIR'))).onTap, isNull);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('config.entry.INSTANCE_NAME'))).onTap, isNotNull);

    // Set an override: the other override is sent along.
    await tester.tap(find.byKey(const ValueKey('config.entry.INSTANCE_NAME')));
    await tester.pumpAndSettle();
    expect(find.text('Override'), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Env: Repolupe')), findsOneWidget);
    expect(find.byKey(const ValueKey('config.override.remove')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('config.override.value')), 'Acme Docs');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('config.override.save')));
    await _pumpUntil(tester, find.text('Config updated.'));
    expect(server.requests.last.$1, '/api/v1/config');
    expect(server.requests.last.$2, {'OCR_ENGINE': 'none', 'INSTANCE_NAME': 'Acme Docs'});
    await tester.pumpAndSettle();
    expect(find.text('Override'), findsNothing);
    // The response is shown, and the instance name is loaded again.
    expect(find.text('Override: Acme Docs', findRichText: true), findsOneWidget);
    for (var i = 0; i < 100 && container.read(instanceNameProvider).data != 'Acme Docs'; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(container.read(instanceNameProvider).data, 'Acme Docs');
    clearSnackBars();

    // An enumerated key offers its choices; removing the override sends the map without it.
    await tester.tap(find.byKey(const ValueKey('config.entry.OCR_ENGINE')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('config.override.choice')), findsOneWidget);
    expect(find.byKey(const ValueKey('config.override.value')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('config.override.remove')));
    await _pumpUntil(tester, find.text('Config updated.'));
    expect(server.requests.last.$1, '/api/v1/config');
    expect(server.requests.last.$2, {'INSTANCE_NAME': 'Acme Docs'});
    await tester.pumpAndSettle();
    expect(find.text('Override: none', findRichText: true), findsNothing);
    expect(find.text('Override: Acme Docs', findRichText: true), findsOneWidget);
    clearSnackBars();

    // Choose an engine from the dropdown.
    await tester.tap(find.byKey(const ValueKey('config.entry.OCR_ENGINE')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('config.override.choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('mistral').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('config.override.save')));
    await _pumpUntil(tester, find.text('Config updated.'));
    expect(server.requests.last.$1, '/api/v1/config');
    expect(server.requests.last.$2, {'INSTANCE_NAME': 'Acme Docs', 'OCR_ENGINE': 'mistral'});
    await tester.pumpAndSettle();
    expect(find.text('Override: mistral', findRichText: true), findsOneWidget);
    clearSnackBars();

    // A rejected value: the API's message is shown and the dialog stays open with nothing changed.
    server.rejectedValue = 'abc';
    await tester.tap(find.byKey(const ValueKey('config.entry.OCR_SCAN_CONFIDENCE')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('config.override.value')), 'abc');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('config.override.save')));
    await _pumpUntil(tester, find.byKey(const ValueKey('config.override.error')));
    expect(find.text('OCR_SCAN_CONFIDENCE: expected a number between 0 and 1'), findsOneWidget);
    expect(server.requests.last.$1, '/api/v1/config');
    expect(server.requests.last.$2, {'INSTANCE_NAME': 'Acme Docs', 'OCR_ENGINE': 'mistral', 'OCR_SCAN_CONFIDENCE': 'abc'});
    await tester.pumpAndSettle();
    expect(find.text('Override'), findsOneWidget);
    expect(find.byKey(const ValueKey('config.override.save')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Override: abc', findRichText: true), findsNothing);
  });
}
