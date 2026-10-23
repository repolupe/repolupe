import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/settings/repositories_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/fake_repository.dart';
import 'support/fake_user.dart';
import 'support/persistence.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _docsId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';
const _notesId = '0199a8d4-6d5e-7c3a-9b1f-000000000002';

/// Pumps until [finder] finds something, letting the requests to the server run meanwhile.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

/// A server with a user and their repositories; the requests are recorded by their path.
class _FakeServer {
  final HttpServer server;
  List<Map<String, dynamic>> repositories;
  final requests = <String>[];

  _FakeServer(this.server, {required this.repositories}) {
    server.listen(_handle);
  }

  static Future<_FakeServer> start(WidgetTester tester, {required List<Map<String, dynamic>> repositories}) async {
    final fake = (await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      return _FakeServer(server, repositories: repositories);
    }))!;
    addTearDown(() => fake.server.close(force: true));
    return fake;
  }

  String get apiUrl => 'http://127.0.0.1:${server.port}';

  Future<void> _handle(HttpRequest request) async {
    await utf8.decodeStream(request);
    final response = request.response;
    response.headers.contentType = ContentType.json;
    requests.add(request.uri.path);
    final path = request.uri.path;
    final one = repositories.where((r) => path == '/api/v1/repositories/${r['id']}').firstOrNull;
    if (request.method == 'GET' && path == '/api/v1/me') {
      response.write(jsonEncode(fakeUser(id: _userId)));
    } else if (request.method == 'GET' && path == '/api/v1/repositories') {
      response.write(jsonEncode(repositories));
    } else if (request.method == 'GET' && one != null) {
      response.write(jsonEncode(one));
    } else {
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
          home: const RepositoriesPage(),
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

  testWidgets('the repositories page lists, filters, follows a sync and opens a repository', (tester) async {
    final server = await _FakeServer.start(
      tester,
      repositories: [
        fakeRepository(id: _docsId, ownerId: _userId, name: 'docs', description: 'The handbook'),
        fakeRepository(id: _notesId, ownerId: _userId, name: 'notes', local: true, syncStatus: 'PENDING', gitSize: null, lfsSize: null),
      ],
    );
    await _pumpPage(tester, server);

    await _pumpUntil(tester, find.text('2 Repositories'));
    expect(find.text('docs'), findsOneWidget);
    expect(find.text('https://github.com/acme/docs.git (main)'), findsOneWidget);
    expect(find.text('12.3 kB'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('notes'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);

    // Filtered by the description, then nothing matches.
    await tester.enterText(find.byKey(const ValueKey('repositories.search')), 'handbook');
    await tester.pump();
    expect(find.byKey(const ValueKey('repositories.$_docsId')), findsOneWidget);
    expect(find.byKey(const ValueKey('repositories.$_notesId')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('repositories.search')), 'zzz');
    await tester.pump();
    expect(find.text('No repositories match your search.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('repositories.search')), '');
    await tester.pump();

    // The pending repository is synced in the meantime: the list is loaded again after 5 seconds.
    final requestsBefore = server.requests.length;
    server.repositories = [
      server.repositories.first,
      fakeRepository(id: _notesId, ownerId: _userId, name: 'notes', local: true, gitSize: 500, lfsSize: 0),
    ];
    await tester.pump(const Duration(seconds: 5));
    await _pumpUntil(tester, find.text('500 B'));
    expect(find.text('Ready'), findsNWidgets(2));
    expect(server.requests.skip(requestsBefore), contains('/api/v1/repositories'));

    // Nothing syncs any more, so the polling stops.
    final requestsAfter = server.requests.length;
    await tester.pump(const Duration(seconds: 6));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(server.requests.length, requestsAfter);

    // Opens the repository's page.
    await tester.tap(find.byKey(const ValueKey('repositories.$_docsId')));
    await _pumpUntil(tester, find.text('Here you can update the repository details, trigger sync jobs and share the repository with other users.'));
    expect(server.requests.last, '/api/v1/repositories/$_docsId');
    expect(find.text('The handbook'), findsOneWidget);
  });

  testWidgets('without repositories, the page shows the empty state', (tester) async {
    final server = await _FakeServer.start(tester, repositories: []);
    await _pumpPage(tester, server);
    await _pumpUntil(tester, find.text('No repositories yet'));
    expect(find.byKey(const ValueKey('repositories.new')), findsOneWidget);
    expect(find.byKey(const ValueKey('repositories.search')), findsNothing);
  });
}
