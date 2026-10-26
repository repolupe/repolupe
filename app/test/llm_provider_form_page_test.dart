import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/settings/admin/llm_provider_form_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/fake_llm.dart';
import 'support/fake_user.dart';
import 'support/persistence.dart';
import 'support/rust.dart';

const _adminId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _providerId = '0199a8d4-6d5e-7c3a-9b1f-000000000010';

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

/// Opens the name picker of the create form and waits for its suggestions, which come from the Rust crate.
Future<void> _openNamePicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('providerForm.name')));
  await _pumpUntil(tester, find.byKey(const ValueKey('providerNamePicker.Anthropic')));
  await tester.pumpAndSettle();
}

/// A server with an admin that accepts providers; the POSTs are recorded by their path with their body.
class _FakeServer {
  final HttpServer server;
  final requests = <(String, Map<String, dynamic>?)>[];

  _FakeServer(this.server) {
    server.listen(_handle);
  }

  static Future<_FakeServer> start(WidgetTester tester) async {
    final fake = (await tester.runAsync(() async => _FakeServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0))))!;
    addTearDown(() => fake.server.close(force: true));
    return fake;
  }

  String get apiUrl => 'http://127.0.0.1:${server.port}';

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
      case ('POST', '/api/v1/llm-providers'):
        response.statusCode = 201;
        response.write(
          jsonEncode(
            fakeLlmProvider(
              id: _providerId,
              name: body!['name'] as String,
              apiFormat: body['api_format'] as String,
              baseUrl: body['base_url'] as String? ?? 'https://api.anthropic.com',
              hasKey: body['api_key'] != null,
              currency: body['currency'] as String?,
            ),
          ),
        );
      case ('POST', '/api/v1/llm-providers/$_providerId/update'):
        response.write(
          jsonEncode(
            fakeLlmProvider(
              id: _providerId,
              name: body!['name'] as String,
              apiFormat: body['api_format'] as String,
              baseUrl: body['base_url'] as String? ?? 'https://api.anthropic.com',
              keyHint: 'ab12',
              currency: body['currency'] as String?,
            ),
          ),
        );
      default:
        response.statusCode = 404;
        response.write(jsonEncode(fakeError('NOT_FOUND', 'Not found')));
    }
    await response.close();
  }
}

/// Pumps a list page for the admin of [server], whose user is loaded; the tests push the form above it.
Future<RefenaContainer> _pumpApp(WidgetTester tester, _FakeServer server) async {
  tester.view.physicalSize = const Size(600, 1600);
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
          home: const Scaffold(body: Text('the list')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('creating a provider checks the name, sends the fields, and pops with the provider', (tester) async {
    final server = await _FakeServer.start(tester);
    LlmProviderDto? created;
    final container = await _pumpApp(tester, server);
    unawaited(
      container.global.dispatchAsync(NavigateAction.push<LlmProviderDto>(const LlmProviderFormPage.create())).then((p) => created = p),
    );
    await _settle(tester);

    // The form starts with the OpenAI format, the default currency and no key field choice.
    expect(find.byKey(const ValueKey('providerForm.key.keep')), findsNothing);
    expect(find.text('API key'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('providerForm.save')));
    await _pumpUntil(tester, find.text('Missing name'));
    expect(server.requests, isEmpty);
    container.read(snackBarProvider).key.currentState!.clearSnackBars();

    // A name of its own, which no suggestion matches.
    await _openNamePicker(tester);
    await tester.enterText(find.byKey(const ValueKey('providerNamePicker.search')), ' step6 ');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerNamePicker.Anthropic')), findsNothing);
    expect(find.text('Use “step6”'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('providerNamePicker.custom')));
    await tester.pumpAndSettle();
    expect(find.text('step6'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('providerForm.format')));
    await tester.pumpAndSettle();
    // The menu shows the items again above the field's own.
    await tester.tap(find.descendant(of: find.byType(Scrollable).last, matching: find.text('Anthropic')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('providerForm.currency')), 'eu');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerForm.currency.USD')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('providerForm.currency.EUR')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('providerForm.apiKey')), 'sk-123');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('providerForm.save')));
    await _pumpUntil(tester, find.text('Provider created.'));
    expect(server.requests.single.$1, '/api/v1/llm-providers');
    expect(server.requests.single.$2, {'name': 'step6', 'api_format': 'ANTHROPIC', 'base_url': null, 'api_key': 'sk-123', 'currency': 'EUR'});
    await _settle(tester);
    expect(find.byKey(const ValueKey('providerForm.save')), findsNothing);
    expect(created?.name, 'step6');
    expect(created?.apiKey, isNotNull);
  });

  testWidgets('choosing a common provider fills in the form', (tester) async {
    final server = await _FakeServer.start(tester);
    final container = await _pumpApp(tester, server);
    unawaited(container.global.dispatchAsync(NavigateAction.push(const LlmProviderFormPage.create())));
    await _settle(tester);

    // All of them while the search is empty, then only the matching ones.
    await _openNamePicker(tester);
    await tester.enterText(find.byKey(const ValueKey('providerNamePicker.search')), 'ak');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerNamePicker.Anthropic')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('providerNamePicker.Aki')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerNamePicker.search')), findsNothing);
    expect(find.text('Aki'), findsOneWidget);
    expect(find.text('https://aki.io/anthropic'), findsOneWidget);
    expect(find.text('EUR'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('providerForm.save')));
    await _pumpUntil(tester, find.text('Provider created.'));
    expect(server.requests.single.$2, {
      'name': 'Aki',
      'api_format': 'ANTHROPIC',
      'base_url': 'https://aki.io/anthropic',
      'api_key': null,
      'currency': 'EUR',
    });
  });

  testWidgets('clearing the currency creates a provider without prices', (tester) async {
    final server = await _FakeServer.start(tester);
    final container = await _pumpApp(tester, server);
    unawaited(container.global.dispatchAsync(NavigateAction.push(const LlmProviderFormPage.create())));
    await _settle(tester);

    // The keyboard's "done" takes the name as it is.
    await _openNamePicker(tester);
    await tester.enterText(find.byKey(const ValueKey('providerNamePicker.search')), 'local');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('local'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('providerForm.currency.clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerForm.currency.clear')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('providerForm.save')));
    await _pumpUntil(tester, find.text('Provider created.'));
    expect(server.requests.single.$2?['currency'], isNull);
  });

  testWidgets('editing a provider renames it in place instead of picking a name', (tester) async {
    final server = await _FakeServer.start(tester);
    final provider = llmProviderOf(fakeLlmProvider(id: _providerId, name: 'Anthropic', keyHint: 'ab12'));
    final container = await _pumpApp(tester, server);
    unawaited(container.global.dispatchAsync(NavigateAction.push(LlmProviderFormPage.edit(provider: provider))));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('providerForm.name')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerNamePicker.search')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('providerForm.name')), 'Claude');
    await tester.pump();
    expect(find.text('Claude'), findsOneWidget);
  });

  testWidgets('editing a provider keeps the key unless a new one is chosen, which must not be empty', (tester) async {
    final server = await _FakeServer.start(tester);
    final provider = llmProviderOf(fakeLlmProvider(id: _providerId, name: 'Anthropic', keyHint: 'ab12'));
    final container = await _pumpApp(tester, server);
    unawaited(container.global.dispatchAsync(NavigateAction.push(LlmProviderFormPage.edit(provider: provider))));
    await _settle(tester);

    // The official base URL is left to the hint, the key is kept by default.
    expect(find.text('(currently •••• ab12)'), findsOneWidget);
    expect(find.byKey(const ValueKey('providerForm.apiKey')), findsNothing);
    expect(find.byKey(const ValueKey('providerForm.hostChanged')), findsNothing);

    // A new key must be entered when chosen.
    await tester.tap(find.byKey(const ValueKey('providerForm.key.set')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerForm.apiKey')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('providerForm.save')));
    await _pumpUntil(tester, find.text('Missing API key'));
    expect(server.requests, isEmpty);
    container.read(snackBarProvider).key.currentState!.clearSnackBars();

    // Another host cannot keep the key.
    await tester.tap(find.byKey(const ValueKey('providerForm.key.keep')));
    await tester.enterText(find.byKey(const ValueKey('providerForm.baseUrl')), 'https://proxy.example.com/v1');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerForm.hostChanged')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('providerForm.baseUrl')), '');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerForm.hostChanged')), findsNothing);

    // Kept: the name changes, the key is not sent.
    await tester.enterText(find.byKey(const ValueKey('providerForm.name')), 'Anthropic 2');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('providerForm.save')));
    await _pumpUntil(tester, find.text('Provider updated.'));
    expect(server.requests.single.$1, '/api/v1/llm-providers/$_providerId/update');
    expect(server.requests.single.$2, {
      'name': 'Anthropic 2',
      'api_format': 'ANTHROPIC',
      'base_url': null,
      'api_key': {'action': 'KEEP'},
      'currency': 'USD',
    });
    await _settle(tester);
    expect(find.text('the list'), findsOneWidget);
  });
}
