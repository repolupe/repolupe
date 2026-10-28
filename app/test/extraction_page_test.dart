import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/config_page.dart';
import 'package:app/pages/settings/admin/extraction_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/config.dart';
import 'package:app/src/rust/third_party/repolupe/dto/extraction.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/api.dart';
import 'support/fake_admin.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _adminId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _docsId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';
const _familyId = '0199a8d4-6d5e-7c3a-9b1f-000000000002';

/// The API of an admin with the overview and the documents of all repositories; the list actions are recorded by
/// their filter, offset and limit, the retries by their blob.
class _FakeApi {
  ExtractionOverviewDto overview;
  List<ExtractionDocumentDto> documents;
  final lists = <(DocumentFilter, int, int)>[];
  final retries = <String>[];
  int overviews = 0;

  _FakeApi({required this.overview, required this.documents});

  /// The category of a fake document, like the API's filter.
  static DocumentFilter _category(ExtractionDocumentDto document) {
    if (document.document.conversion != null) {
      return DocumentFilter.pending;
    }
    return document.document.extraction?.status == DocumentExtractionStatus.failed ? DocumentFilter.failed : DocumentFilter.converted;
  }

  /// Answers the actions of the page with this API.
  void answer(ApiMocks mock) {
    mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _adminId, userName: 'alice', role: UserRole.admin)));
    mock.on<ApiGetExtractionOverviewAction>((state, _) {
      overviews++;
      return (state, overview);
    });
    mock.on<ApiListExtractionDocumentsAction>((state, action) {
      lists.add((action.filter, action.offset, action.limit));
      final matching = [
        for (final document in documents)
          if (action.filter == DocumentFilter.all || _category(document) == action.filter) document,
      ];
      return (state, ExtractionDocumentPageDto(items: matching.skip(action.offset).take(action.limit).toList(), total: matching.length));
    });
    mock.on<ApiRetryDocumentExtractionAction>((state, action) {
      retries.add(action.blobOid);
      return state;
    });
    // For the config page the hint links to.
    mock.on<ApiGetConfigAction>((state, _) => (state, <ConfigEntryDto>[]));
  }
}

/// Opens the page for the admin of [api], whose user is loaded.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeApi api) async {
  // Tall enough for the overview and a page of documents.
  tester.view.physicalSize = const Size(600, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: _adminId),
      api: api.answer,
    ),
  ))!;
  await container.redux(meProvider).dispatchAsync(RefreshMeAction());

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
  // The page loads after its first frame.
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the extraction page shows the totals, the paused warning, filters, loads more, retries, and polls while converting', (
    tester,
  ) async {
    final api = _FakeApi(
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
        fakeExtractionDocument(path: 'docs/b.pdf', repositoryId: _docsId, extraction: DocumentExtractionStatus.failed, error: 'The PDF is encrypted'),
        fakeExtractionDocument(
          path: 'docs/c.pdf',
          repositoryId: _docsId,
          conversion: DocumentConversionStatus.converting,
          startedAt: '2026-10-21T12:00:00+00:00',
          extraction: null,
        ),
        fakeExtractionDocument(path: 'docs/d.pdf', repositoryId: _docsId, conversion: DocumentConversionStatus.waiting),
        fakeExtractionDocument(
          path: 'docs/e.pdf',
          repositoryId: _docsId,
          conversion: DocumentConversionStatus.skipped,
          skipReason: DocumentSkipReason.lfsObjectMissing,
          extraction: null,
        ),
        for (var i = 0; i < 26; i++)
          fakeExtractionDocument(path: 'scans/$i.pdf', repositoryId: _familyId, repositoryName: 'family', ownerName: 'bob', ocr: true),
      ],
    );
    final container = await _pumpPage(tester, api);
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
    expect(api.lists, [(DocumentFilter.all, 0, 25)]);
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
    await tester.pumpAndSettle();
    expect(find.text('scans/25.pdf'), findsOneWidget);
    expect(api.lists.last, (DocumentFilter.all, 25, 25));
    expect(find.text('scans/20.pdf'), findsOneWidget);
    expect(find.byKey(const ValueKey('extraction.more')), findsNothing);

    // The filter is sent to the API.
    await tester.tap(find.byKey(const ValueKey('extraction.filter.failed')));
    await tester.pumpAndSettle();
    expect(api.lists.last, (DocumentFilter.failed, 0, 25));
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
    final listsBefore = api.lists.length;
    final overviewsBefore = api.overviews;
    await tester.tap(find.byKey(const ValueKey('extraction.document.$_docsId.docs/b.pdf.retry')));
    await tester.pump();
    expect(find.text('The document is converted again.'), findsOneWidget);
    expect(api.retries, ['blob-docs/b.pdf']);
    expect(api.lists.length, listsBefore + 1);
    expect(api.overviews, overviewsBefore + 1);
    await tester.pumpAndSettle();
    clearSnackBars();

    // While a document is converting, the overview and the documents are loaded again every 5 seconds.
    final overviewsBeforePoll = api.overviews;
    api.overview = fakeExtractionOverview(documents: 30, converted: 30);
    api.documents = [
      for (final document in api.documents)
        ExtractionDocumentDto(
          repository: document.repository,
          blobOid: document.blobOid,
          document: RepositoryDocumentDto(
            path: document.document.path,
            extraction: DocumentExtractionDto(
              status: DocumentExtractionStatus.completed,
              ocr: false,
              extractedAt: DateTime.parse('2026-10-21T12:00:00+00:00'),
            ),
          ),
        ),
    ];
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('Converted (30)'), findsOneWidget);
    expect(api.overviews, overviewsBeforePoll + 1);
    expect(find.text('Idle, no documents are waiting'), findsOneWidget);
    expect(find.byKey(const ValueKey('extraction.paused')), findsNothing);
    expect(find.text('Failed (0)'), findsOneWidget);
    expect(find.text('No documents in this category.'), findsOneWidget);

    // Nothing is waiting any more, so the polling stops.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    expect(api.overviews, overviewsBeforePoll + 1);

    // The hint links to the configuration.
    await tester.tapOnText(find.textRange.ofSubstring('config'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ConfigPage), findsOneWidget);
  });
}
