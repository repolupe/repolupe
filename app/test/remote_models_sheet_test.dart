import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/widget/admin/remote_models_sheet.dart';
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
const _existingId = '0199a8d4-6d5e-7c3a-9b1f-000000000020';

/// Pumps until [finder] finds something, letting the requests to the server run meanwhile.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

/// Pumps until the requests of the sheet are done (no progress indicator any more) and its animations have settled.
Future<void> _settle(WidgetTester tester) async {
  final progress = find.byType(CircularProgressIndicator);
  for (var i = 0; i < 100 && progress.evaluate().isNotEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  expect(progress, findsNothing);
  await tester.pumpAndSettle();
}

/// A server with an admin whose provider lists [remoteModels] (or fails with [listError]) and rejects adding the
/// models named in [rejected]; the POSTs are recorded by their path with their body.
class _FakeServer {
  final HttpServer server;
  final List<Map<String, dynamic>> remoteModels;
  final String? listError;
  final Set<String> rejected;
  final requests = <(String, Map<String, dynamic>?)>[];
  var _nextId = 100;

  /// A fresh model id.
  String _newId() => '0199a8d4-6d5e-7c3a-9b1f-${(_nextId++).toString().padLeft(12, '0')}';

  _FakeServer(this.server, {required this.remoteModels, required this.listError, required this.rejected}) {
    server.listen(_handle);
  }

  static Future<_FakeServer> start(
    WidgetTester tester, {
    List<Map<String, dynamic>> remoteModels = const [],
    String? listError,
    Set<String> rejected = const {},
  }) async {
    final fake = (await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      return _FakeServer(server, remoteModels: remoteModels, listError: listError, rejected: rejected);
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
      case ('GET', '/api/v1/llm-providers/$_providerId/remote-models') when listError != null:
        response.statusCode = 502;
        response.write(jsonEncode(fakeError('REMOTE_UNREACHABLE', listError!)));
      case ('GET', '/api/v1/llm-providers/$_providerId/remote-models'):
        response.write(jsonEncode(remoteModels));
      case ('POST', '/api/v1/llm-providers/$_providerId/models') when rejected.contains(body!['api_name']):
        response.statusCode = 422;
        response.write(jsonEncode(fakeError('VALIDATION_ERROR', 'Unsupported model')));
      case ('POST', '/api/v1/llm-providers/$_providerId/models'):
        response.statusCode = 201;
        response.write(
          jsonEncode(
            fakeLlmModel(
              id: _newId(),
              providerId: _providerId,
              apiName: body!['api_name'] as String,
              displayName: body['display_name'] as String?,
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

/// A page with a button that opens the sheet for [provider] and records how it was closed.
class _Host extends StatefulWidget {
  final LlmProviderDto provider;

  const _Host({required this.provider});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  RemoteModelsOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: const ValueKey('open'),
          onPressed: () async {
            final result = await RemoteModelsSheet.show(context, provider: widget.provider, becomesDefault: true);
            setState(() {
              outcome = result;
            });
          },
          child: Text('outcome: $outcome'),
        ),
      ),
    );
  }
}

/// Opens the sheet of [provider] for the admin of [server], whose user is loaded.
Future<RefenaContainer> _pumpSheet(WidgetTester tester, _FakeServer server, LlmProviderDto provider) async {
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
          home: _Host(provider: provider),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  // The sheet fetches after its first frame, so its progress indicator shows only then.
  await tester.pump();
  await tester.pump();
  await _settle(tester);
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the sheet lists the models of the server, marks the added ones, and adds the selected ones', (tester) async {
    final server = await _FakeServer.start(
      tester,
      remoteModels: [
        fakeRemoteModel(apiName: 'gpt-a', displayName: 'GPT A'),
        fakeRemoteModel(apiName: 'gpt-b'),
        fakeRemoteModel(apiName: 'existing'),
      ],
    );
    final provider = llmProviderOf(
      fakeLlmProvider(
        id: _providerId,
        name: 'OpenAI',
        apiFormat: 'OPENAI',
        models: [fakeLlmModel(id: _existingId, providerId: _providerId, apiName: 'existing')],
      ),
    );
    await _pumpSheet(tester, server, provider);

    expect(find.text('Models of OpenAI'), findsOneWidget);
    expect(find.text('GPT A'), findsOneWidget);
    expect(find.text('gpt-a'), findsOneWidget);
    expect(find.text('gpt-b'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('remoteModels.existing'))).enabled, isFalse);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('remoteModels.existing'))).value, isTrue);
    expect(find.text('Added'), findsOneWidget);
    final add = find.byKey(const ValueKey('remoteModels.add'));
    expect(tester.widget<FilledButton>(add).enabled, isFalse);

    // The search narrows the list, "select all" takes the matches.
    await tester.enterText(find.byKey(const ValueKey('remoteModels.search')), 'gpt');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('remoteModels.existing')), findsNothing);
    expect(find.text('Select all 2 matches'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remoteModels.selectAll')));
    await tester.pumpAndSettle();
    expect(find.text('Add 2 models'), findsOneWidget);
    expect(find.textContaining('the first model added becomes the default'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remoteModels.gpt-b')));
    await tester.pumpAndSettle();
    expect(find.text('Add 1 model'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remoteModels.gpt-b')));
    await tester.pumpAndSettle();

    await tester.tap(add);
    await _pumpUntil(tester, find.text('2 models added.'));
    expect(server.requests.map((r) => r.$1), ['/api/v1/llm-providers/$_providerId/models', '/api/v1/llm-providers/$_providerId/models']);
    expect(server.requests.map((r) => r.$2), [
      {
        'api_name': 'gpt-a',
        'display_name': 'GPT A',
        'max_output_tokens': null,
        'input_price': null,
        'output_price': null,
        'cache_read_price': null,
        'cache_write_price': null,
      },
      {
        'api_name': 'gpt-b',
        'display_name': null,
        'max_output_tokens': null,
        'input_price': null,
        'output_price': null,
        'cache_read_price': null,
        'cache_write_price': null,
      },
    ]);
    await _settle(tester);
    expect(find.text('outcome: RemoteModelsOutcome.added'), findsOneWidget);
  });

  testWidgets('the sheet stays open with the error when some models cannot be added', (tester) async {
    final server = await _FakeServer.start(
      tester,
      remoteModels: [
        fakeRemoteModel(apiName: 'good'),
        fakeRemoteModel(apiName: 'bad'),
      ],
      rejected: {'bad'},
    );
    final provider = llmProviderOf(fakeLlmProvider(id: _providerId, name: 'OpenAI', apiFormat: 'OPENAI'));
    await _pumpSheet(tester, server, provider);

    await tester.tap(find.byKey(const ValueKey('remoteModels.selectAll')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remoteModels.add')));
    // Shown in the sheet: a snack bar would be behind its barrier.
    await _pumpUntil(tester, find.byKey(const ValueKey('remoteModels.addError')));
    expect(find.text('Added 1 of 2 models. bad: The request is invalid.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Added'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('remoteModels.good'))).enabled, isFalse);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('remoteModels.bad'))).value, isTrue);
    expect(find.text('Add 1 model'), findsOneWidget);

    // Closing reports the one that was added.
    await tester.tap(find.byKey(const ValueKey('remoteModels.cancel')));
    await tester.pumpAndSettle();
    expect(find.text('outcome: RemoteModelsOutcome.added'), findsOneWidget);
  });

  testWidgets('the sheet shows the error of the server and offers to add a model by name', (tester) async {
    final server = await _FakeServer.start(tester, listError: 'Could not send the request: connection refused');
    final provider = llmProviderOf(fakeLlmProvider(id: _providerId, name: 'Broken', apiFormat: 'OPENAI', baseUrl: 'http://127.0.0.1:9'));
    await _pumpSheet(tester, server, provider);

    expect(find.text('Could not reach the remote server, or it responded with an error.'), findsOneWidget);
    expect(find.text('You can still add the models by name.'), findsOneWidget);
    expect(find.byKey(const ValueKey('remoteModels.retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('remoteModels.add')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('remoteModels.addByName')));
    await tester.pumpAndSettle();
    expect(find.text('outcome: RemoteModelsOutcome.addByName'), findsOneWidget);
  });
}
