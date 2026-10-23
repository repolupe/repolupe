import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/settings/admin/llm_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/fake_llm.dart';
import 'support/fake_user.dart';
import 'support/persistence.dart';
import 'support/rust.dart';

const _adminId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _anthropicId = '0199a8d4-6d5e-7c3a-9b1f-000000000010';
const _localId = '0199a8d4-6d5e-7c3a-9b1f-000000000011';
const _opusId = '0199a8d4-6d5e-7c3a-9b1f-000000000020';
const _haikuId = '0199a8d4-6d5e-7c3a-9b1f-000000000021';

/// Pumps until [finder] finds something, letting the requests to the server run meanwhile. The frames advance the
/// clock, so that a snack bar being dismissed makes way for the next one.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

/// Pumps until [finder] finds nothing any more.
Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isNotEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsNothing);
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

/// A server with an admin and the providers; the POSTs are recorded by their path with their body.
class _FakeServer {
  final HttpServer server;
  List<Map<String, dynamic>> providers;
  final requests = <(String, Map<String, dynamic>?)>[];

  _FakeServer(this.server, {required this.providers}) {
    server.listen(_handle);
  }

  static Future<_FakeServer> start(WidgetTester tester, {required List<Map<String, dynamic>> providers}) async {
    final fake = (await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      return _FakeServer(server, providers: providers);
    }))!;
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
      case ('GET', '/api/v1/llm-providers'):
        response.write(jsonEncode(providers));
      case ('POST', '/api/v1/default-model'):
        final modelId = body!['model_id'] as String;
        providers = [
          for (final provider in providers)
            {
              ...provider,
              'models': [
                for (final model in provider['models'] as List<Map<String, dynamic>>) {...model, 'is_default': model['id'] == modelId},
              ],
            },
        ];
        response.statusCode = 204;
      case ('POST', '/api/v1/models/$_opusId/delete'):
        providers = [
          for (final provider in providers)
            {
              ...provider,
              'models': [
                for (final model in provider['models'] as List<Map<String, dynamic>>)
                  if (model['id'] != _opusId) model,
              ],
            },
        ];
        response.statusCode = 204;
      case ('POST', '/api/v1/llm-providers/$_localId/delete'):
        providers = [
          for (final provider in providers)
            if (provider['id'] != _localId) provider,
        ];
        response.statusCode = 204;
      default:
        response.statusCode = 404;
        response.write(jsonEncode(fakeError('NOT_FOUND', 'Not found')));
    }
    await response.close();
  }
}

/// Opens the page for the admin of [server], whose user is loaded.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeServer server) async {
  // Tall enough for both providers with their models, so that the lower card is built too.
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
          home: const LlmPage(),
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

  testWidgets('the LLM page shows the providers with their models, changes the default, and deletes a model and a provider', (
    tester,
  ) async {
    final server = await _FakeServer.start(
      tester,
      providers: [
        fakeLlmProvider(
          id: _anthropicId,
          name: 'Anthropic',
          keyHint: 'ab12',
          models: [
            fakeLlmModel(
              id: _opusId,
              providerId: _anthropicId,
              apiName: 'claude-opus-5-5',
              displayName: 'Claude Opus 5.5',
              inputPrice: '15',
              outputPrice: '75',
              cacheReadPrice: '1.5',
              isDefault: true,
            ),
            fakeLlmModel(id: _haikuId, providerId: _anthropicId, apiName: 'claude-haiku'),
          ],
        ),
        fakeLlmProvider(id: _localId, name: 'Local', apiFormat: 'OPENAI', baseUrl: 'http://localhost:11434/v1', hasKey: false, currency: null),
      ],
    );
    final container = await _pumpPage(tester, server);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();

    expect(find.text('2 Models'), findsOneWidget);
    expect(find.text('Anthropic'), findsNWidgets(2)); // The provider's name and its API format.
    expect(find.text('•••• ab12'), findsOneWidget);
    expect(find.text('Claude Opus 5.5'), findsOneWidget);
    expect(find.text('claude-opus-5-5'), findsOneWidget);
    expect(find.text(r'$15.00 in / $75.00 out'), findsOneWidget);
    expect(find.text(r'Cache read $1.50, cache write $15.00'), findsOneWidget);
    expect(find.text('claude-haiku'), findsOneWidget);
    expect(find.text('Price per 1M tokens: Not set'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('http://localhost:11434/v1'), findsOneWidget);
    expect(find.text('None (its models have no prices)'), findsOneWidget);
    expect(find.text('No models yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('llm.noDefault')), findsNothing);

    // The star of the default model is filled and does nothing; the other one makes its model the default.
    final opusStar = find.byKey(const ValueKey('llm.model.$_opusId.default'));
    final haikuStar = find.byKey(const ValueKey('llm.model.$_haikuId.default'));
    expect(tester.widget<IconButton>(opusStar).onPressed, isNull);
    expect(((tester.widget<IconButton>(opusStar).icon) as Icon).icon, Icons.star);
    expect(tester.widget<IconButton>(haikuStar).onPressed, isNotNull);
    expect(((tester.widget<IconButton>(haikuStar).icon) as Icon).icon, Icons.star_border);
    await tester.tap(haikuStar);
    await _pumpUntil(tester, find.text('Default model changed.'));
    expect(server.requests.last.$1, '/api/v1/default-model');
    expect(server.requests.last.$2, {'model_id': _haikuId});
    // The providers are loaded again without a progress indicator.
    await _pumpUntil(tester, find.descendant(of: haikuStar, matching: find.byIcon(Icons.star)));
    await _settle(tester);
    expect(tester.widget<IconButton>(haikuStar).onPressed, isNull);
    expect(((tester.widget<IconButton>(opusStar).icon) as Icon).icon, Icons.star_border);
    clearSnackBars();

    // Delete a model after confirming.
    await tester.tap(find.byKey(const ValueKey('llm.model.$_opusId.delete')));
    await tester.pumpAndSettle();
    expect(find.textContaining('The model Claude Opus 5.5 will be deleted.'), findsOneWidget);
    expect(find.textContaining('It is the default model'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('llm.model.delete.confirm')));
    await _pumpUntil(tester, find.text('Model deleted.'));
    expect(server.requests.last.$1, '/api/v1/models/$_opusId/delete');
    await _pumpUntilGone(tester, find.text('Claude Opus 5.5'));
    await _settle(tester);
    expect(find.text('1 Model'), findsOneWidget);
    clearSnackBars();

    // Delete a provider after typing its name.
    await tester.tap(find.byKey(const ValueKey('llm.provider.$_localId.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete provider'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The provider Local will be deleted, together with its 0 models.'), findsOneWidget);
    final confirm = find.byKey(const ValueKey('llm.provider.delete.confirm'));
    expect(tester.widget<FilledButton>(confirm).enabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('llm.provider.delete.verification')), 'Local');
    await tester.pump();
    await tester.tap(confirm);
    await _pumpUntil(tester, find.text('Provider deleted.'));
    expect(server.requests.last.$1, '/api/v1/llm-providers/$_localId/delete');
    await _pumpUntilGone(tester, find.text('http://localhost:11434/v1'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('llm.provider.$_localId')), findsNothing);
    expect(find.byKey(const ValueKey('llm.provider.$_anthropicId')), findsOneWidget);
  });

  testWidgets('the LLM page without providers offers to create one, and warns without a default model', (tester) async {
    final server = await _FakeServer.start(tester, providers: []);
    await _pumpPage(tester, server);
    expect(find.text('No providers yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('llm.empty.newProvider')), findsOneWidget);
    expect(find.byKey(const ValueKey('llm.newProvider')), findsNothing);

    // A provider whose model is not the default.
    server.providers = [
      fakeLlmProvider(
        id: _anthropicId,
        models: [fakeLlmModel(id: _haikuId, providerId: _anthropicId, apiName: 'claude-haiku')],
      ),
    ];
    await tester.pumpWidget(const SizedBox());
    await _pumpPage(tester, server);
    expect(find.byKey(const ValueKey('llm.noDefault')), findsOneWidget);
    expect(find.byKey(const ValueKey('llm.newProvider')), findsOneWidget);
  });
}
