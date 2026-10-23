import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/settings/repository_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
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
const _otherUserId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f99';
const _repositoryId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';

/// Pumps until [finder] finds something, letting the requests to the server run meanwhile. The frames advance the
/// clock, so that a snack bar being dismissed makes way for the next one.
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

/// A server with a user and one repository; the POSTs are recorded by their path with their body.
class _FakeServer {
  final HttpServer server;
  Map<String, dynamic>? repository;
  final requests = <(String, Map<String, dynamic>?)>[];

  _FakeServer(this.server, {required this.repository}) {
    server.listen(_handle);
  }

  static Future<_FakeServer> start(WidgetTester tester, {required Map<String, dynamic>? repository}) async {
    final fake = (await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      return _FakeServer(server, repository: repository);
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
    final repository = this.repository;
    switch ((request.method, request.uri.path)) {
      case ('GET', '/api/v1/me'):
        response.write(jsonEncode(fakeUser(id: _userId)));
      case ('GET', '/api/v1/repositories/$_repositoryId') when repository != null:
        response.write(jsonEncode(repository));
      case ('GET', '/api/v1/repositories/$_repositoryId/documents') when repository != null:
        response.write(jsonEncode({'documents': [], 'paused_until': null}));
      case ('GET', '/api/v1/repositories/$_repositoryId/users') when repository != null:
        response.write(jsonEncode([]));
      case ('POST', '/api/v1/repositories/$_repositoryId/sync') when repository != null:
        response.statusCode = 202;
      case ('POST', '/api/v1/repositories/$_repositoryId/update') when repository != null:
        final remote = body!['remote'] as Map<String, dynamic>?;
        final token = remote?['token'] as Map<String, dynamic>?;
        this.repository = {
          ...repository,
          'name': body['name'],
          'description': body['description'],
          'allow_commits': body['allow_commits'],
          if (remote != null)
            'remote': {
              'url': remote['url'],
              'branch': remote['branch'],
              'poll_interval_seconds': remote['poll_interval_seconds'],
              'token': switch (token!['action']) {
                'KEEP' => (repository['remote'] as Map<String, dynamic>)['token'],
                'SET' => {'hint': (token['value'] as String).substring(token['value'].length - 4)},
                _ => null,
              },
            },
        };
        response.write(jsonEncode(this.repository));
      case ('POST', '/api/v1/repositories/$_repositoryId/delete') when repository != null:
        this.repository = null;
        response.statusCode = 204;
      case ('POST', '/api/v1/repositories/$_repositoryId/users/$_userId/delete') when repository != null:
        this.repository = null;
        response.statusCode = 204;
      default:
        response.statusCode = 404;
        response.write(jsonEncode(fakeError('NOT_FOUND', 'Repository not found')));
    }
    await response.close();
  }
}

/// Opens the page above a list page for the user of [server], whose user is loaded.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeServer server) async {
  // Tall enough for the whole page, so that the rows of the sync card are built too.
  tester.view.physicalSize = const Size(600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
          home: const Scaffold(body: Text('the list')),
        ),
      ),
    ),
  );
  unawaited(container.global.dispatchAsync(NavigateAction.push(RepositoryPage(id: UuidValue.fromString(_repositoryId)))));
  await tester.pump();
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the owner syncs, edits (keeping, removing and setting the token) and deletes the repository', (tester) async {
    final server = await _FakeServer.start(
      tester,
      repository: fakeRepository(
        id: _repositoryId,
        ownerId: _userId,
        name: 'docs',
        description: 'The handbook',
        hasToken: true,
        tokenHint: 'ab12',
        syncStatus: 'FAILED',
        lastError: 'Remote not reachable',
        lfsSize: 2000,
      ),
    );
    final container = await _pumpPage(tester, server);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();

    await _pumpUntil(tester, find.text('Here you can update the repository details, trigger sync jobs and share the repository with other users.'));
    // The page is hit-testable once the push transition is over.
    await _settle(tester);
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
    await _pumpUntil(tester, find.text('Sync requested.'));
    expect(server.requests.last.$1, '/api/v1/repositories/$_repositoryId/sync');
    await _settle(tester);
    clearSnackBars();

    // Edit the description, keeping the token.
    await tester.tap(find.byKey(const ValueKey('repository.edit')));
    await _settle(tester);
    expect(find.text('Keep current token (•••• ab12)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('repositoryForm.description')), 'The new handbook');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repositoryForm.save')));
    await _pumpUntil(tester, find.text('Repository updated.'));
    expect(server.requests.last.$1, '/api/v1/repositories/$_repositoryId/update');
    expect(server.requests.last.$2, {
      'name': 'docs',
      'description': 'The new handbook',
      'remote': {
        'url': 'https://github.com/acme/docs.git',
        'branch': 'main',
        'poll_interval_seconds': 900,
        'token': {'action': 'KEEP'},
      },
      'allow_commits': true,
    });
    await _settle(tester);
    expect(find.text('The new handbook'), findsOneWidget);
    clearSnackBars();

    // Remove the token.
    await tester.tap(find.byKey(const ValueKey('repository.edit')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('repositoryForm.token.remove')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repositoryForm.save')));
    await _pumpUntil(tester, find.text('Repository updated.'));
    expect((server.requests.last.$2!['remote'] as Map<String, dynamic>)['token'], {'action': 'REMOVE'});
    await _settle(tester);
    expect(find.text('None (public)'), findsOneWidget);
    clearSnackBars();

    // Set a new token, which is required once chosen.
    await tester.tap(find.byKey(const ValueKey('repository.edit')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('repositoryForm.token.keep')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('repositoryForm.token.set')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repositoryForm.save')));
    await _pumpUntil(tester, find.text('Missing token'));
    clearSnackBars();
    await tester.enterText(find.byKey(const ValueKey('repositoryForm.token')), 'ghp_secret1234');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repositoryForm.save')));
    await _pumpUntil(tester, find.text('Repository updated.'));
    expect((server.requests.last.$2!['remote'] as Map<String, dynamic>)['token'], {'action': 'SET', 'value': 'ghp_secret1234'});
    await _settle(tester);
    expect(find.text('Set (•••• 1234)'), findsOneWidget);
    clearSnackBars();

    // Delete, after typing the name.
    await tester.tap(find.byKey(const ValueKey('repository.delete')));
    await _settle(tester);
    final confirm = find.byKey(const ValueKey('repository.delete.confirm'));
    expect(tester.widget<FilledButton>(confirm).enabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('repository.delete.verification')), 'doc');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).enabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('repository.delete.verification')), 'docs');
    await tester.pump();
    await tester.tap(confirm);
    await _pumpUntil(tester, find.text('Repository deleted.'));
    expect(server.requests.last.$1, '/api/v1/repositories/$_repositoryId/delete');
    await _settle(tester);
    expect(find.text('the list'), findsOneWidget);
    expect(find.byKey(const ValueKey('repository.body')), findsNothing);
  });

  testWidgets('a user the repository is shared with leaves it', (tester) async {
    final server = await _FakeServer.start(
      tester,
      repository: fakeRepository(id: _repositoryId, ownerId: _otherUserId, name: 'docs', local: true, nextSyncAt: null),
    );
    await _pumpPage(tester, server);

    await _pumpUntil(tester, find.text('This repository is shared with you. Here you can see its details and sync status.'));
    // The page is hit-testable once the push transition is over.
    await _settle(tester);
    expect(find.text('Shared with you'), findsOneWidget);
    expect(find.text('None (local repository on this server)'), findsOneWidget);
    expect(find.text('After each commit'), findsOneWidget);
    expect(find.byKey(const ValueKey('repository.edit')), findsNothing);
    expect(find.byKey(const ValueKey('repository.syncNow')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('repository.leave')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('repository.leave.confirm')));
    await _pumpUntil(tester, find.text('You left the repository.'));
    expect(server.requests.last.$1, '/api/v1/repositories/$_repositoryId/users/$_userId/delete');
    await _settle(tester);
    expect(find.text('the list'), findsOneWidget);
  });

  testWidgets('a repository that no longer exists closes the page', (tester) async {
    final server = await _FakeServer.start(tester, repository: null);
    await _pumpPage(tester, server);
    await _pumpUntil(tester, find.text('Repository not found'));
    await _settle(tester);
    expect(find.text('the list'), findsOneWidget);
  });
}
