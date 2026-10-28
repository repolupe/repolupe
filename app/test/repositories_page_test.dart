import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/repositories_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/fake_repository.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _docsId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';
const _notesId = '0199a8d4-6d5e-7c3a-9b1f-000000000002';

/// The API of a user and their repositories; the actions on the repositories are recorded. The documents and the
/// users of a repository are not found.
class _FakeApi {
  List<RepositoryDto> repositories;
  final requests = <Object>[];

  _FakeApi({required this.repositories});

  /// Answers the actions of [apiProvider].
  void answer(ApiMocks mock) {
    mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _userId)));
    mock.on<ApiListRepositoriesAction>((state, action) {
      requests.add(action);
      return (state, repositories);
    });
    mock.on<ApiGetRepositoryAction>((state, action) {
      requests.add(action);
      final repository = repositories.where((r) => r.id == action.id).firstOrNull;
      if (repository == null) {
        throw apiError(ErrorCode.notFound, status: 404);
      }
      return (state, repository);
    });
    mock.on<ApiListRepositoryDocumentsAction>((state, action) {
      requests.add(action);
      throw apiError(ErrorCode.notFound, status: 404);
    });
    mock.on<ApiListRepositoryUsersAction>((state, action) {
      requests.add(action);
      throw apiError(ErrorCode.notFound, status: 404);
    });
  }
}

/// Opens the page for the user of [api], whose user is loaded.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeApi api) async {
  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: _userId),
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
    final api = _FakeApi(
      repositories: [
        fakeRepository(id: _docsId, ownerId: _userId, name: 'docs', description: 'The handbook'),
        fakeRepository(
          id: _notesId,
          ownerId: _userId,
          name: 'notes',
          local: true,
          syncStatus: RepositorySyncStatus.pending,
          gitSize: null,
          lfsSize: null,
        ),
      ],
    );
    await _pumpPage(tester, api);

    await tester.pump();
    expect(find.text('2 Repositories'), findsOneWidget);
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
    final requestsBefore = api.requests.length;
    api.repositories = [
      api.repositories.first,
      fakeRepository(id: _notesId, ownerId: _userId, name: 'notes', local: true, gitSize: 500, lfsSize: 0),
    ];
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('500 B'), findsOneWidget);
    expect(find.text('Ready'), findsNWidgets(2));
    expect(api.requests.skip(requestsBefore), contains(isA<ApiListRepositoriesAction>()));

    // Nothing syncs any more, so the polling stops.
    final requestsAfter = api.requests.length;
    await tester.pump(const Duration(seconds: 6));
    expect(api.requests.length, requestsAfter);

    // Opens the repository's page.
    await tester.tap(find.byKey(const ValueKey('repositories.$_docsId')));
    await tester.pumpAndSettle();
    expect(
      find.text('Here you can update the repository details, trigger sync jobs and share the repository with other users.'),
      findsOneWidget,
    );
    expect(api.requests.last, isA<ApiGetRepositoryAction>().having((a) => a.id, 'id', UuidValue.fromString(_docsId)));
    expect(find.text('The handbook'), findsOneWidget);
  });

  testWidgets('without repositories, the page shows the empty state', (tester) async {
    final api = _FakeApi(repositories: []);
    await _pumpPage(tester, api);
    await tester.pump();
    expect(find.text('No repositories yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('repositories.new')), findsOneWidget);
    expect(find.byKey(const ValueKey('repositories.search')), findsNothing);
  });
}
