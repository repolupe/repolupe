import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/widget/repositories/repository_documents_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/fake_repository.dart';
import 'support/fake_user.dart';
import 'support/persistence.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _repositoryId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';

/// Pumps until [finder] finds something, letting the requests to the server run meanwhile.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

/// A server with one repository whose documents are [documents], counting how often they were listed.
class _FakeServer {
  final HttpServer server;
  List<Map<String, dynamic>> documents;
  String? pausedUntil;
  int lists = 0;

  _FakeServer(this.server, {required this.documents}) {
    server.listen(_handle);
  }

  static Future<_FakeServer> start(WidgetTester tester, {required List<Map<String, dynamic>> documents}) async {
    final fake = (await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      return _FakeServer(server, documents: documents);
    }))!;
    addTearDown(() => fake.server.close(force: true));
    return fake;
  }

  String get apiUrl => 'http://127.0.0.1:${server.port}';

  Future<void> _handle(HttpRequest request) async {
    await utf8.decodeStream(request);
    final response = request.response;
    response.headers.contentType = ContentType.json;
    switch ((request.method, request.uri.path)) {
      case ('GET', '/api/v1/repositories/$_repositoryId/documents'):
        lists++;
        response.write(jsonEncode({'documents': documents, 'paused_until': pausedUntil}));
      default:
        response.statusCode = 404;
        response.write(jsonEncode(fakeError('NOT_FOUND', 'Repository not found')));
    }
    await response.close();
  }
}

/// Shows the card for the repository of [server] at [headCommitSha]; pumping it again with another commit keeps
/// its state, like the page does when the repository is loaded again.
Future<RefenaContainer> _pumpCard(WidgetTester tester, _FakeServer server, {RefenaContainer? container, String? headCommitSha = 'abc'}) async {
  if (container == null) {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final account = Account(
      apiUrl: server.apiUrl,
      token: 'session-token',
      user: AccountUser(id: _userId, userName: 'alice'),
    );
    final persistence = (await tester.runAsync(() => mockPersistence(account: account)))!;
    container = RefenaContainer(overrides: [persistenceProvider.overrideWithValue(persistence)]);
    container.redux(apiProvider).dispatch(ApiSetAccountAction(account));
  }
  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          navigatorKey: container.read(navigationProvider).key,
          scaffoldMessengerKey: container.read(snackBarProvider).key,
          home: Scaffold(
            body: ListView(
              children: [RepositoryDocumentsCard(repositoryId: UuidValue.fromString(_repositoryId), headCommitSha: headCommitSha)],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('lists the documents with their status, filters them, shows the details, and polls while some are pending', (tester) async {
    final server = await _FakeServer.start(
      tester,
      documents: [
        fakeDocument(path: 'docs/a.pdf', ocr: true),
        fakeDocument(path: 'docs/b.pdf', extraction: 'FAILED', error: 'The PDF is encrypted'),
        fakeDocument(path: 'docs/c.pdf', conversion: 'CONVERTING', startedAt: '2026-10-21T12:00:00+00:00', extraction: null),
        fakeDocument(path: 'docs/d.pdf', conversion: 'WAITING'),
        fakeDocument(
          path: 'docs/e.pdf',
          conversion: 'SKIPPED',
          skipReason: 'LFS_OBJECT_MISSING',
          retryAt: '2026-10-21T12:10:00+00:00',
          extraction: null,
        ),
      ],
    );
    final container = await _pumpCard(tester, server);
    await _pumpUntil(tester, find.text('All (5)'));
    expect(server.lists, 1);
    expect(find.text('Converted (1)'), findsOneWidget);
    expect(find.text('Failed (1)'), findsOneWidget);
    expect(find.text('Pending (3)'), findsOneWidget);
    expect(find.text('Converted'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Converting'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Not available'), findsOneWidget);

    // Only the failed documents.
    await tester.tap(find.byKey(const ValueKey('repository.documents.filter.failed')));
    await tester.pumpAndSettle();
    expect(find.text('docs/b.pdf'), findsOneWidget);
    expect(find.text('docs/a.pdf'), findsNothing);
    expect(find.text('docs/c.pdf'), findsNothing);

    // The details of the failed one.
    await tester.tap(find.text('docs/b.pdf'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repository.documents.details')), findsOneWidget);
    expect(find.text('The PDF is encrypted'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repository.documents.details')), findsNothing);

    // The details of a skipped one, with its reason.
    await tester.tap(find.byKey(const ValueKey('repository.documents.filter.pending')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('docs/e.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('The file is stored with Git LFS and could not be downloaded.'), findsOneWidget);
    expect(find.text('Tried again'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // While documents are pending, they are loaded again every 5 seconds.
    server.documents = [for (final document in server.documents) fakeDocument(path: document['path'] as String)];
    await tester.pump(const Duration(seconds: 6));
    await _pumpUntil(tester, find.text('Pending (0)'));
    expect(server.lists, 2);
    expect(find.text('No documents in this category.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('repository.documents.filter.all')));
    await tester.pumpAndSettle();
    expect(find.text('Converted'), findsNWidgets(5));

    // Nothing is pending any more, so the polling stops.
    await tester.pump(const Duration(seconds: 6));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 6));
    expect(server.lists, 2);

    // A new head commit loads the documents of that commit.
    server.documents = [fakeDocument(path: 'docs/f.pdf')];
    await _pumpCard(tester, server, container: container, headCommitSha: 'def');
    await _pumpUntil(tester, find.text('docs/f.pdf'));
    expect(server.lists, 3);
    expect(find.text('All (1)'), findsOneWidget);
  });

  testWidgets('shows more documents on request, and a repository that is not synced yet', (tester) async {
    final server = await _FakeServer.start(tester, documents: [for (var i = 0; i < 12; i++) fakeDocument(path: 'doc-$i.pdf')]);
    final container = await _pumpCard(tester, server);
    await _pumpUntil(tester, find.text('All (12)'));
    expect(find.text('doc-9.pdf'), findsOneWidget);
    expect(find.text('doc-10.pdf'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('repository.documents.more')));
    await tester.pumpAndSettle();
    expect(find.text('doc-11.pdf'), findsOneWidget);
    expect(find.byKey(const ValueKey('repository.documents.more')), findsNothing);

    server.documents = [];
    await _pumpCard(tester, server, container: container, headCommitSha: null);
    await _pumpUntil(tester, find.text('Not synced yet'));
  });
}
