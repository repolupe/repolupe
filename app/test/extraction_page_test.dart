import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/settings/admin/config_page.dart';
import 'package:app/pages/settings/admin/extraction_page.dart';
import 'package:app/service/api_service.dart';
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
const _docsId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';
const _familyId = '0199a8d4-6d5e-7c3a-9b1f-000000000002';

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

/// A server with an admin, the overview and the documents of all repositories; the list requests are recorded by
/// their query, the POSTs by their path with their body.
class _FakeServer {
  final HttpServer server;
  Map<String, dynamic> overview;
  List<Map<String, dynamic>> documents;
  final lists = <Map<String, String>>[];
  final requests = <(String, Map<String, dynamic>?)>[];
  int overviews = 0;

  _FakeServer(this.server, {required this.overview, required this.documents}) {
    server.listen(_handle);
  }

  static Future<_FakeServer> start(
    WidgetTester tester, {
    required Map<String, dynamic> overview,
    required List<Map<String, dynamic>> documents,
  }) async {
    final fake = (await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      return _FakeServer(server, overview: overview, documents: documents);
    }))!;
    addTearDown(() => fake.server.close(force: true));
    return fake;
  }

  String get apiUrl => 'http://127.0.0.1:${server.port}';

  /// The category of a fake document, like the API's filter.
  static String _category(Map<String, dynamic> document) {
    if (document['conversion'] != null) {
      return 'PENDING';
    }
    return (document['extraction'] as Map<String, dynamic>?)?['status'] == 'FAILED' ? 'FAILED' : 'CONVERTED';
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
      case ('GET', '/api/v1/document-extraction'):
        overviews++;
        response.write(jsonEncode(overview));
      case ('GET', '/api/v1/document-extraction/documents'):
        final query = request.uri.queryParameters;
        lists.add(query);
        final filter = query['filter'] ?? 'ALL';
        final offset = int.parse(query['offset'] ?? '0');
        final limit = int.parse(query['limit'] ?? '25');
        final matching = [
          for (final document in documents)
            if (filter == 'ALL' || _category(document) == filter) document,
        ];
        response.write(jsonEncode({'items': matching.skip(offset).take(limit).toList(), 'total': matching.length}));
      case ('POST', '/api/v1/document-extraction/retry'):
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
  // Tall enough for the overview and a page of documents.
  tester.view.physicalSize = const Size(600, 3200);
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
          home: const ExtractionPage(),
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

  testWidgets('the extraction page shows the totals, the paused warning, filters, loads more, retries, and polls while converting', (
    tester,
  ) async {
    final server = await _FakeServer.start(
      tester,
      overview: fakeExtractionOverview(
        documents: 30,
        converted: 26,
        failed: 1,
        waiting: 2,
        skipped: 1,
        converting: fakeConvertingDocument(path: 'docs/c.pdf', repositoryId: _docsId, repositoryName: 'docs', ownerName: 'alice'),
        pausedUntil: '2026-10-21T12:05:00+00:00',
        pauseReason: 'Mistral: 429 Too Many Requests',
      ),
      documents: [
        fakeExtractionDocument(path: 'docs/b.pdf', repositoryId: _docsId, extraction: 'FAILED', error: 'The PDF is encrypted'),
        fakeExtractionDocument(
          path: 'docs/c.pdf',
          repositoryId: _docsId,
          conversion: 'CONVERTING',
          startedAt: '2026-10-21T12:00:00+00:00',
          extraction: null,
        ),
        fakeExtractionDocument(path: 'docs/d.pdf', repositoryId: _docsId, conversion: 'WAITING'),
        fakeExtractionDocument(path: 'docs/e.pdf', repositoryId: _docsId, conversion: 'SKIPPED', skipReason: 'LFS_OBJECT_MISSING', extraction: null),
        for (var i = 0; i < 26; i++)
          fakeExtractionDocument(path: 'scans/$i.pdf', repositoryId: _familyId, repositoryName: 'family', ownerName: 'bob', ocr: true),
      ],
    );
    final container = await _pumpPage(tester, server);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();

    // The overview.
    expect(find.text('30 Documents'), findsOneWidget);
    expect(find.byKey(const ValueKey('extraction.paused')), findsOneWidget);
    expect(find.text('The OCR service is unavailable'), findsOneWidget);
    expect(find.textContaining('Conversions are paused until'), findsOneWidget);
    expect(find.text('Mistral: 429 Too Many Requests'), findsOneWidget);
    expect(find.textContaining('Converting docs/c.pdf in docs (alice), started'), findsOneWidget);
    expect(find.text('30 total'), findsOneWidget);
    expect(find.text('26 converted'), findsOneWidget);
    expect(find.text('1 failed'), findsOneWidget);
    expect(find.text('2 waiting'), findsOneWidget);
    expect(find.text('1 not available'), findsOneWidget);
    expect(find.text('xberg-1/paddle/en/0.5'), findsOneWidget);

    // The first page of the documents, with the counts of the filters from the totals.
    expect(server.lists, [
      {'filter': 'ALL', 'offset': '0', 'limit': '25'},
    ]);
    expect(find.text('All (30)'), findsOneWidget);
    expect(find.text('Converted (26)'), findsOneWidget);
    expect(find.text('Failed (1)'), findsOneWidget);
    expect(find.text('Pending (3)'), findsOneWidget);
    expect(find.text('docs/b.pdf'), findsOneWidget);
    expect(find.text('docs (alice)'), findsNWidgets(4));
    expect(find.text('scans/20.pdf'), findsOneWidget);
    expect(find.text('scans/21.pdf'), findsNothing);
    expect(find.text('family (bob)'), findsNWidgets(21));
    // Only the failed and the skipped document can be converted again.
    expect(find.byKey(const ValueKey('extraction.document.$_docsId.docs/b.pdf.retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('extraction.document.$_docsId.docs/e.pdf.retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('extraction.document.$_docsId.docs/c.pdf.retry')), findsNothing);
    expect(find.byKey(const ValueKey('extraction.document.$_docsId.docs/d.pdf.retry')), findsNothing);
    expect(find.byKey(const ValueKey('extraction.document.$_familyId.scans/0.pdf.retry')), findsNothing);

    // Load more appends the next page.
    expect(find.text('Load more (5 remaining)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('extraction.more')));
    await _pumpUntil(tester, find.text('scans/25.pdf'));
    await _settle(tester);
    expect(server.lists.last, {'filter': 'ALL', 'offset': '25', 'limit': '25'});
    expect(find.text('scans/20.pdf'), findsOneWidget);
    expect(find.byKey(const ValueKey('extraction.more')), findsNothing);

    // The filter is sent to the server.
    await tester.tap(find.byKey(const ValueKey('extraction.filter.failed')));
    for (var i = 0; i < 100 && server.lists.last['filter'] != 'FAILED'; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _settle(tester);
    expect(server.lists.last, {'filter': 'FAILED', 'offset': '0', 'limit': '25'});
    expect(find.text('docs/b.pdf'), findsOneWidget);
    expect(find.text('scans/0.pdf'), findsNothing);
    expect(find.text('docs/c.pdf'), findsNothing);

    // The details of the failed document.
    await tester.tap(find.text('docs/b.pdf'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repository.documents.details')), findsOneWidget);
    expect(find.text('The PDF is encrypted'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repository.documents.details')), findsNothing);

    // Converting it again sends its blob and loads the page again.
    final listsBefore = server.lists.length;
    final overviewsBefore = server.overviews;
    await tester.tap(find.byKey(const ValueKey('extraction.document.$_docsId.docs/b.pdf.retry')));
    await _pumpUntil(tester, find.text('The document is converted again.'));
    expect(server.requests.last.$1, '/api/v1/document-extraction/retry');
    expect(server.requests.last.$2, {'blob_oid': 'blob-docs/b.pdf'});
    for (var i = 0; i < 100 && server.lists.length == listsBefore; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(server.lists.length, listsBefore + 1);
    expect(server.overviews, overviewsBefore + 1);
    await _settle(tester);
    clearSnackBars();

    // While a document is converting, the overview and the documents are loaded again every 5 seconds.
    final overviewsBeforePoll = server.overviews;
    server.overview = fakeExtractionOverview(documents: 30, converted: 30);
    server.documents = [
      for (final document in server.documents)
        {
          ...document,
          'conversion': null,
          'extraction': {'status': 'COMPLETED', 'ocr': false, 'error': null, 'extracted_at': '2026-10-21T12:00:00+00:00'},
        },
    ];
    await tester.pump(const Duration(seconds: 6));
    await _pumpUntil(tester, find.text('Converted (30)'));
    expect(server.overviews, overviewsBeforePoll + 1);
    expect(find.text('Idle, no documents are waiting'), findsOneWidget);
    expect(find.byKey(const ValueKey('extraction.paused')), findsNothing);
    expect(find.text('Failed (0)'), findsOneWidget);
    expect(find.text('No documents in this category.'), findsOneWidget);

    // Nothing is waiting any more, so the polling stops.
    await tester.pump(const Duration(seconds: 6));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 6));
    expect(server.overviews, overviewsBeforePoll + 1);

    // The hint links to the configuration.
    await tester.tapOnText(find.textRange.ofSubstring('config'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ConfigPage), findsOneWidget);
  });
}
