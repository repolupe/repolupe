import 'dart:async';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/repository_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/api/mirror.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/extraction.dart';
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
const _otherUserId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f99';
const _repositoryId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';

/// The API of a user and one [repository] (`null` once it is gone); the changes are recorded in [requests].
class _FakeApi {
  RepositoryDto? repository;
  final requests = <Object>[];

  _FakeApi({required this.repository});

  /// The answers to the actions of the page.
  void answer(ApiMocks mock) {
    mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _userId)));
    mock.on<ApiGetRepositoryAction>((state, action) => (state, _repository(action.id)));
    mock.on<ApiListRepositoryDocumentsAction>((state, action) {
      _repository(action.id);
      return (state, const RepositoryDocumentsDto(documents: []));
    });
    mock.on<ApiListRepositoryUsersAction>((state, action) {
      _repository(action.id);
      return (state, <RepositoryUserDto>[]);
    });
    mock.on<ApiSyncRepositoryAction>((state, action) {
      requests.add(action);
      return state;
    });
    mock.on<ApiUpdateRepositoryAction>((state, action) {
      requests.add(action);
      final updated = _updated(_repository(action.id), action.request);
      repository = updated;
      return (state, updated);
    });
    mock.on<ApiDeleteRepositoryAction>((state, action) {
      requests.add(action);
      repository = null;
      return state;
    });
    mock.on<ApiRemoveRepositoryUserAction>((state, action) {
      requests.add(action);
      repository = null;
      return state;
    });
  }

  /// The repository if it is [id] and still exists, like the server answers it.
  RepositoryDto _repository(UuidValue id) {
    final repository = this.repository;
    if (repository == null || id != UuidValue.fromString(_repositoryId)) {
      throw apiError(ErrorCode.notFound, status: 404, message: 'Repository not found');
    }
    return repository;
  }
}

/// [repository] with the changes of [request], a set token having the last four characters as its hint.
RepositoryDto _updated(RepositoryDto repository, UpdateRepositoryRequest request) {
  final remote = request.remote;
  return RepositoryDto(
    id: repository.id,
    ownerId: repository.ownerId,
    name: request.name,
    description: request.description,
    remote: remote == null
        ? null
        : RemoteSettingsDto(
            url: remote.url,
            branch: remote.branch,
            pollIntervalSeconds: remote.pollIntervalSeconds,
            token: switch (remote.token) {
              TokenChange_Keep() => repository.remote?.token,
              TokenChange_Set(:final value) => RepositoryTokenDto(hint: value.substring(value.length - 4)),
              TokenChange_Remove() => null,
            },
          ),
    allowCommits: request.allowCommits,
    canCommit: repository.canCommit,
    syncStatus: repository.syncStatus,
    syncStartedAt: repository.syncStartedAt,
    headCommitSha: repository.headCommitSha,
    lastSyncedAt: repository.lastSyncedAt,
    gitSize: repository.gitSize,
    lfsSize: repository.lfsSize,
    lastError: repository.lastError,
    nextSyncAt: repository.nextSyncAt,
    createdAt: repository.createdAt,
    updatedAt: repository.updatedAt,
  );
}

/// Opens the page above a list page for the user of [api], whose user is loaded.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeApi api) async {
  // Tall enough for the whole page, so that the rows of the sync card are built too.
  tester.view.physicalSize = const Size(600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
          home: const Scaffold(body: Text('the list')),
        ),
      ),
    ),
  );
  unawaited(container.global.dispatchAsync(NavigateAction.push(RepositoryPage(id: UuidValue.fromString(_repositoryId)))));
  await tester.pump();
  return container;
}

/// Matches an action on the repository of the page.
TypeMatcher<A> _on<A extends Object>(UuidValue Function(A action) id) => isA<A>().having(id, 'id', UuidValue.fromString(_repositoryId));

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the owner syncs, edits (keeping, removing and setting the token) and deletes the repository', (tester) async {
    final api = _FakeApi(
      repository: fakeRepository(
        id: _repositoryId,
        ownerId: _userId,
        name: 'docs',
        description: 'The handbook',
        hasToken: true,
        tokenHint: 'ab12',
        syncStatus: RepositorySyncStatus.failed,
        lastError: 'Remote not reachable',
        lfsSize: 2000,
      ),
    );
    final container = await _pumpPage(tester, api);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();
    UpdateRepositoryRequest lastUpdate() => (api.requests.last as ApiUpdateRepositoryAction).request;

    // The page is hit-testable once the push transition is over.
    await tester.pumpAndSettle();
    expect(find.text('Here you can update the repository details, trigger sync jobs and share the repository with other users.'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('14.3 kB'), findsOneWidget);
    expect(find.text('Git 12.3 kB, LFS 2 kB'), findsOneWidget);
    expect(find.text('Last sync failed'), findsOneWidget);
    expect(find.text('Remote not reachable'), findsOneWidget);
    expect(find.text('Set (•••• ab12)'), findsOneWidget);
    expect(find.text('Every 15 minutes'), findsOneWidget);
    expect(find.text('0123456'), findsOneWidget);
    expect(find.text('Enabled (the model can propose changes)'), findsOneWidget);
    expect(find.byKey(const ValueKey('repository.leave')), findsNothing);

    // Sync now.
    await tester.tap(find.byKey(const ValueKey('repository.syncNow')));
    await tester.pumpAndSettle();
    expect(find.text('Sync requested.'), findsOneWidget);
    expect(api.requests.last, _on<ApiSyncRepositoryAction>((a) => a.id));
    clearSnackBars();

    // Edit the description, keeping the token.
    await tester.tap(find.byKey(const ValueKey('repository.edit')));
    await tester.pumpAndSettle();
    expect(find.text('Keep current token (•••• ab12)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('repositoryForm.description')), 'The new handbook');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repositoryForm.save')));
    await tester.pumpAndSettle();
    expect(find.text('Repository updated.'), findsOneWidget);
    expect(api.requests.last, _on<ApiUpdateRepositoryAction>((a) => a.id));
    expect(
      lastUpdate(),
      const UpdateRepositoryRequest(
        name: 'docs',
        description: 'The new handbook',
        remote: RemoteSettingsChange(
          url: 'https://github.com/acme/docs.git',
          branch: 'main',
          pollIntervalSeconds: 900,
          token: TokenChange.keep(),
        ),
        allowCommits: true,
      ),
    );
    expect(find.text('The new handbook'), findsOneWidget);
    clearSnackBars();

    // Remove the token.
    await tester.tap(find.byKey(const ValueKey('repository.edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('repositoryForm.token.remove')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repositoryForm.save')));
    await tester.pumpAndSettle();
    expect(find.text('Repository updated.'), findsOneWidget);
    expect(lastUpdate().remote!.token, const TokenChange.remove());
    expect(find.text('None (public)'), findsOneWidget);
    clearSnackBars();

    // Set a new token, which is required once chosen.
    await tester.tap(find.byKey(const ValueKey('repository.edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repositoryForm.token.keep')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('repositoryForm.token.set')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repositoryForm.save')));
    await tester.pumpAndSettle();
    expect(find.text('Missing token'), findsWidgets);
    clearSnackBars();
    await tester.enterText(find.byKey(const ValueKey('repositoryForm.token')), 'ghp_secret1234');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repositoryForm.save')));
    await tester.pumpAndSettle();
    expect(find.text('Repository updated.'), findsOneWidget);
    expect(lastUpdate().remote!.token, const TokenChange.set_(value: 'ghp_secret1234'));
    expect(find.text('Set (•••• 1234)'), findsOneWidget);
    clearSnackBars();

    // Delete, after typing the name.
    await tester.tap(find.byKey(const ValueKey('repository.delete')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('repository.delete.confirm'));
    expect(tester.widget<FilledButton>(confirm).enabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('repository.delete.verification')), 'doc');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).enabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('repository.delete.verification')), 'docs');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Repository deleted.'), findsOneWidget);
    expect(api.requests.last, _on<ApiDeleteRepositoryAction>((a) => a.id));
    expect(find.text('the list'), findsOneWidget);
    expect(find.byKey(const ValueKey('repository.body')), findsNothing);
  });

  testWidgets('a user the repository is shared with leaves it', (tester) async {
    final api = _FakeApi(
      repository: fakeRepository(id: _repositoryId, ownerId: _otherUserId, name: 'docs', local: true, nextSyncAt: null),
    );
    await _pumpPage(tester, api);

    // The page is hit-testable once the push transition is over.
    await tester.pumpAndSettle();
    expect(find.text('This repository is shared with you. Here you can see its details and sync status.'), findsOneWidget);
    expect(find.text('Shared with you'), findsOneWidget);
    expect(find.text('None (local repository on this server)'), findsOneWidget);
    expect(find.text('After each commit'), findsOneWidget);
    expect(find.byKey(const ValueKey('repository.edit')), findsNothing);
    expect(find.byKey(const ValueKey('repository.syncNow')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('repository.leave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('repository.leave.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('You left the repository.'), findsOneWidget);
    expect(
      api.requests.last,
      _on<ApiRemoveRepositoryUserAction>((a) => a.id).having((a) => a.userId, 'userId', UuidValue.fromString(_userId)),
    );
    expect(find.text('the list'), findsOneWidget);
  });

  testWidgets('a repository that no longer exists closes the page', (tester) async {
    await _pumpPage(tester, _FakeApi(repository: null));
    await tester.pumpAndSettle();
    expect(find.text('Repository not found'), findsOneWidget);
    expect(find.text('the list'), findsOneWidget);
  });
}
