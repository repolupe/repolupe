import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/settings/preferences_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/fake_user.dart';
import 'support/persistence.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _providerA = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0a01';
const _providerB = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0b01';
const _modelFast = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0a02';
const _modelSmart = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0b02';

/// Pumps until [finder] finds something, letting the requests to the server run meanwhile. The frames advance the
/// clock, so that a snack bar being dismissed makes way for the next one.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

/// Pumps until the requests of the page are done (no row shows a progress indicator any more) and its animations
/// have settled.
Future<void> _settle(WidgetTester tester) async {
  final progress = find.byType(CircularProgressIndicator);
  for (var i = 0; i < 100 && progress.evaluate().isNotEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  expect(progress, findsNothing);
  await tester.pumpAndSettle();
}

/// A server with a user and the models it lists; the requests that change the user are recorded by their path.
class _FakeServer {
  final HttpServer server;
  List<Map<String, dynamic>> models;
  String? defaultModelId;
  String? locale;
  bool autoCommit = false;
  final requests = <(String, Map<String, dynamic>)>[];

  _FakeServer(this.server, {required this.models}) {
    server.listen(_handle);
  }

  /// Bound and listened to in the real async zone, so that it also answers the requests sent outside the pumps.
  static Future<_FakeServer> start(WidgetTester tester, {required List<Map<String, dynamic>> models}) async {
    final fake = (await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      return _FakeServer(server, models: models);
    }))!;
    addTearDown(() => fake.server.close(force: true));
    return fake;
  }

  String get apiUrl => 'http://127.0.0.1:${server.port}';

  Future<void> _handle(HttpRequest request) async {
    final body = request.method == 'POST' ? jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic> : null;
    final response = request.response;
    response.headers.contentType = ContentType.json;
    if (body != null) {
      requests.add((request.uri.path, body));
    }
    switch ((request.method, request.uri.path)) {
      case ('GET', '/api/v1/me'):
        response.write(jsonEncode(fakeUser(id: _userId, defaultModelId: defaultModelId, locale: locale, autoCommit: autoCommit)));
      case ('GET', '/api/v1/models'):
        response.write(jsonEncode(models));
      case ('POST', '/api/v1/me/default-model'):
        final modelId = body!['model_id'] as String?;
        if (modelId != null && !models.any((m) => m['id'] == modelId)) {
          response.statusCode = 404;
          response.write(jsonEncode(fakeError('UNKNOWN_MODEL', 'Unknown model')));
        } else {
          defaultModelId = modelId;
          response.statusCode = 204;
        }
      case ('POST', '/api/v1/me/locale'):
        locale = body!['locale'] as String?;
        response.statusCode = 204;
      case ('POST', '/api/v1/me/auto-commit'):
        autoCommit = body!['auto_commit'] as bool;
        response.statusCode = 204;
      default:
        response.statusCode = 404;
        response.write(jsonEncode(fakeError('NOT_FOUND', 'Not found')));
    }
    await response.close();
  }
}

/// Opens the page for the user of [server], whose user is loaded.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeServer server) async {
  final account = Account(
    apiUrl: server.apiUrl,
    token: 'session-token',
    user: AccountUser(id: _userId, userName: 'alice'),
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
          home: const PreferencesPage(),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the preferences page sets the model, the language and auto-commit', (tester) async {
    final server = await _FakeServer.start(
      tester,
      models: [
        fakeModel(id: _modelFast, displayName: 'Fast', providerId: _providerA, providerName: 'Alpha', isDefault: true),
        fakeModel(id: _modelSmart, displayName: 'Smart', providerId: _providerB, providerName: 'Beta'),
      ],
    );
    final container = await _pumpPage(tester, server);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();

    // Without a model of their own, the default one is shown once the models are loaded.
    await _pumpUntil(tester, find.text('Default (Fast)'));
    expect(find.text('Device default (en-US)'), findsOneWidget);
    expect(find.byKey(const ValueKey('preferences.autoCommit')), findsOneWidget);

    // A model deleted in the meantime: the models are loaded again, so the sheet no longer offers it.
    await tester.tap(find.byKey(const ValueKey('preferences.model')));
    await _settle(tester);
    expect(find.text('Beta'), findsOneWidget);
    server.models = [server.models.first];
    await tester.tap(find.byKey(const ValueKey('preferences.model.$_modelSmart')));
    await _pumpUntil(tester, find.text('Could not save the model: The model is no longer available.'));
    expect(server.requests.last.$1, '/api/v1/me/default-model');
    expect(server.requests.last.$2, {'model_id': _modelSmart});
    await _settle(tester);
    clearSnackBars();
    await tester.tap(find.byKey(const ValueKey('preferences.model')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('preferences.model.$_modelSmart')), findsNothing);

    // Chosen: shown with its provider.
    await tester.tap(find.byKey(const ValueKey('preferences.model.$_modelFast')));
    await _pumpUntil(tester, find.text('Model updated.'));
    expect(server.requests.last.$1, '/api/v1/me/default-model');
    expect(server.requests.last.$2, {'model_id': _modelFast});
    await _settle(tester);
    expect(find.text('Fast (Alpha)'), findsOneWidget);
    expect(container.read(meProvider)?.defaultModelId.toString(), _modelFast);
    clearSnackBars();

    // The language, then back to the device's.
    await tester.tap(find.byKey(const ValueKey('preferences.locale')));
    await _settle(tester);
    // Named in English; below the fold of the sheet.
    final deCh = find.byKey(const ValueKey('preferences.locale.de-CH'));
    await tester.scrollUntilVisible(deCh, 100, scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(deCh);
    await tester.pumpAndSettle();
    expect(find.text('German (Switzerland) – de-CH'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preferences.locale.de-CH')));
    await _pumpUntil(tester, find.text('Language updated.'));
    expect(server.requests.last.$1, '/api/v1/me/locale');
    expect(server.requests.last.$2, {'locale': 'de-CH'});
    await _settle(tester);
    expect(find.text('de-CH'), findsOneWidget);
    clearSnackBars();
    await tester.tap(find.byKey(const ValueKey('preferences.locale')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('preferences.locale.default')));
    await _pumpUntil(tester, find.text('Language updated.'));
    expect(server.requests.last.$1, '/api/v1/me/locale');
    expect(server.requests.last.$2, {'locale': null});
    await _settle(tester);
    expect(find.text('Device default (en-US)'), findsOneWidget);
    clearSnackBars();

    // Auto-commit on and off.
    await tester.tap(find.byKey(const ValueKey('preferences.autoCommit')));
    await _pumpUntil(tester, find.text('Proposed changes are now applied automatically.'));
    expect(server.requests.last.$1, '/api/v1/me/auto-commit');
    expect(server.requests.last.$2, {'auto_commit': true});
    await _settle(tester);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('preferences.autoCommit'))).value, isTrue);
    clearSnackBars();
    await tester.tap(find.byKey(const ValueKey('preferences.autoCommit')));
    await _pumpUntil(tester, find.text('Proposed changes now wait for you to apply them.'));
    expect(server.requests.last.$1, '/api/v1/me/auto-commit');
    expect(server.requests.last.$2, {'auto_commit': false});
    await _settle(tester);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('preferences.autoCommit'))).value, isFalse);
  });

  testWidgets('without models, the preferences page says so instead of offering a choice', (tester) async {
    final server = await _FakeServer.start(tester, models: []);
    await _pumpPage(tester, server);
    await _pumpUntil(tester, find.text('No models configured'));
    await tester.tap(find.byKey(const ValueKey('preferences.model')));
    await _pumpUntil(tester, find.text('No models configured. Ask an admin to add one.'));
    expect(find.byKey(const ValueKey('preferences.model.default')), findsNothing);
    expect(server.requests, isEmpty);
  });
}
