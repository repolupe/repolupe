import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/extraction.dart';
import 'package:app/widget/repositories/repository_documents_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/fake_repository.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _repositoryId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';

/// The API of one repository whose documents are [documents], counting how often they were listed.
class _FakeApi {
  List<RepositoryDocumentDto> documents;
  int lists = 0;

  _FakeApi({required this.documents});

  /// Answers the listing of the documents, only for the repository (`NOT_FOUND` otherwise, like the server).
  /// Asynchronously like a request, since the card loads them again while it is rebuilt with another commit.
  void answer(ApiMocks mock) {
    mock.on<ApiListRepositoryDocumentsAction>((state, action) async {
      if (action.id != UuidValue.fromString(_repositoryId)) {
        throw apiError(ErrorCode.notFound, status: 404, message: 'Repository not found');
      }
      lists++;
      return (state, RepositoryDocumentsDto(documents: documents));
    });
  }
}

/// Shows the card for the repository of [api] at [headCommitSha]; pumping it again with another commit keeps
/// its state, like the page does when the repository is loaded again.
Future<RefenaContainer> _pumpCard(WidgetTester tester, _FakeApi api, {RefenaContainer? container, String? headCommitSha = 'abc'}) async {
  if (container == null) {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = (await tester.runAsync(
      () => mockContainer(
        account: fakeAccount(userId: _userId),
        api: api.answer,
      ),
    ))!;
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
    final api = _FakeApi(
      documents: [
        fakeDocument(path: 'docs/a.pdf', ocr: true),
        fakeDocument(path: 'docs/b.pdf', extraction: DocumentExtractionStatus.failed, error: 'The PDF is encrypted'),
        fakeDocument(path: 'docs/c.pdf', conversion: DocumentConversionStatus.converting, startedAt: '2026-10-21T12:00:00+00:00', extraction: null),
        fakeDocument(path: 'docs/d.pdf', conversion: DocumentConversionStatus.waiting),
        fakeDocument(
          path: 'docs/e.pdf',
          conversion: DocumentConversionStatus.skipped,
          skipReason: DocumentSkipReason.lfsObjectMissing,
          retryAt: '2026-10-21T12:10:00+00:00',
          extraction: null,
        ),
      ],
    );
    final container = await _pumpCard(tester, api);
    await tester.pump();
    expect(find.text('All (5)'), findsOneWidget);
    expect(api.lists, 1);
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
    api.documents = [for (final document in api.documents) fakeDocument(path: document.path)];
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('Pending (0)'), findsOneWidget);
    expect(api.lists, 2);
    expect(find.text('No documents in this category.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('repository.documents.filter.all')));
    await tester.pumpAndSettle();
    expect(find.text('Converted'), findsNWidgets(5));

    // Nothing is pending any more, so the polling stops.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    expect(api.lists, 2);

    // A new head commit loads the documents of that commit.
    api.documents = [fakeDocument(path: 'docs/f.pdf')];
    await _pumpCard(tester, api, container: container, headCommitSha: 'def');
    await tester.pump();
    expect(find.text('docs/f.pdf'), findsOneWidget);
    expect(api.lists, 3);
    expect(find.text('All (1)'), findsOneWidget);
  });

  testWidgets('shows more documents on request, and a repository that is not synced yet', (tester) async {
    final api = _FakeApi(documents: [for (var i = 0; i < 12; i++) fakeDocument(path: 'doc-$i.pdf')]);
    final container = await _pumpCard(tester, api);
    await tester.pump();
    expect(find.text('All (12)'), findsOneWidget);
    expect(find.text('doc-9.pdf'), findsOneWidget);
    expect(find.text('doc-10.pdf'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('repository.documents.more')));
    await tester.pumpAndSettle();
    expect(find.text('doc-11.pdf'), findsOneWidget);
    expect(find.byKey(const ValueKey('repository.documents.more')), findsNothing);

    api.documents = [];
    await _pumpCard(tester, api, container: container, headCommitSha: null);
    await tester.pump();
    expect(find.text('Not synced yet'), findsOneWidget);
  });
}
