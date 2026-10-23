import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/widget/repositories/repository_users_card.dart';
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
const _bobId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f21';
const _carolId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f22';
const _daveId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f23';
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

/// Pumps until [finder] finds nothing any more, letting the requests to the server run meanwhile.
Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isNotEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsNothing);
}

/// Pumps until the requests of the card are done (no progress indicator any more) and its animations have settled.
Future<void> _settle(WidgetTester tester) async {
  final progress = find.byType(CircularProgressIndicator);
  for (var i = 0; i < 100 && progress.evaluate().isNotEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  expect(progress, findsNothing);
  await tester.pumpAndSettle();
}

/// A server with one repository shared with [users]; the POSTs are recorded by their path with their body.
class _FakeServer {
  final HttpServer server;
  List<Map<String, dynamic>> users;
  final requests = <(String, Map<String, dynamic>?)>[];

  _FakeServer(this.server, {required this.users}) {
    server.listen(_handle);
  }

  static Future<_FakeServer> start(WidgetTester tester, {required List<Map<String, dynamic>> users}) async {
    final fake = (await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      return _FakeServer(server, users: users);
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
      case ('GET', '/api/v1/repositories/$_repositoryId/users'):
        response.write(jsonEncode(users));
      case ('POST', '/api/v1/repositories/$_repositoryId/users'):
        if (body!['user_name_or_email'] == 'dave') {
          users = [...users, fakeRepositoryUser(userId: _daveId, userName: 'dave')];
          response.statusCode = 204;
        } else {
          response.statusCode = 422;
          response.write(jsonEncode(fakeError('UNKNOWN_USER', 'There is no user with this user name or email')));
        }
      case ('POST', '/api/v1/repositories/$_repositoryId/users/$_bobId/update'):
        users = [
          for (final user in users)
            if (user['user_id'] == _bobId) {...user, 'can_commit': body!['can_commit']} else user,
        ];
        response.statusCode = 204;
      case ('POST', '/api/v1/repositories/$_repositoryId/users/$_bobId/delete'):
        users = [
          for (final user in users)
            if (user['user_id'] != _bobId) user,
        ];
        response.statusCode = 204;
      default:
        response.statusCode = 404;
        response.write(jsonEncode(fakeError('NOT_FOUND', 'Repository not found')));
    }
    await response.close();
  }
}

/// Shows the card for the repository of [server].
Future<RefenaContainer> _pumpCard(WidgetTester tester, _FakeServer server, {bool allowCommits = true, bool local = false}) async {
  tester.view.physicalSize = const Size(600, 1600);
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
  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          navigatorKey: container.read(navigationProvider).key,
          scaffoldMessengerKey: container.read(snackBarProvider).key,
          home: Scaffold(
            body: ListView(
              children: [RepositoryUsersCard(repositoryId: UuidValue.fromString(_repositoryId), allowCommits: allowCommits, local: local)],
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

  testWidgets('lists the users, shares with another one, lets a user commit, and stops sharing', (tester) async {
    final server = await _FakeServer.start(
      tester,
      users: [
        fakeRepositoryUser(userId: _bobId, userName: 'bob', email: 'bob@example.com'),
        fakeRepositoryUser(userId: _carolId, userName: 'carol', canCommit: true),
      ],
    );
    final container = await _pumpCard(tester, server);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();

    await _pumpUntil(tester, find.text('bob'));
    await _settle(tester);
    expect(find.textContaining('bob@example.com'), findsOneWidget);
    expect(find.text('carol'), findsOneWidget);
    expect(find.text('Not shared with anyone'), findsNothing);
    expect(find.textContaining("using this repository's access token"), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('repository.users.canCommit.$_bobId'))).value, isFalse);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('repository.users.canCommit.$_carolId'))).value, isTrue);

    // Share: the name is required, an unknown user is reported, then it works.
    await tester.tap(find.byKey(const ValueKey('repository.users.share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('repository.share.confirm')));
    await _pumpUntil(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Missing user name or email')));
    await tester.enterText(find.byKey(const ValueKey('repository.share.user')), 'nobody');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repository.share.confirm')));
    await _pumpUntil(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('No user with this user name or email')));
    expect(find.byType(SnackBar), findsNothing);
    expect(server.requests.last.$1, '/api/v1/repositories/$_repositoryId/users');
    expect(server.requests.last.$2, {'user_name_or_email': 'nobody'});
    await _settle(tester);
    expect(find.byKey(const ValueKey('repository.share.user')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('repository.share.user')), ' dave ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repository.share.confirm')));
    await _pumpUntil(tester, find.text('Repository shared.'));
    expect(server.requests.last.$1, '/api/v1/repositories/$_repositoryId/users');
    expect(server.requests.last.$2, {'user_name_or_email': 'dave'});
    await _pumpUntil(tester, find.text('dave'));
    await _settle(tester);
    clearSnackBars();

    // Let bob commit.
    await tester.tap(find.byKey(const ValueKey('repository.users.canCommit.$_bobId')));
    await _pumpUntil(
      tester,
      find.byWidgetPredicate((w) => w is SwitchListTile && w.key == const ValueKey('repository.users.canCommit.$_bobId') && w.value),
    );
    expect(server.requests.last.$1, '/api/v1/repositories/$_repositoryId/users/$_bobId/update');
    expect(server.requests.last.$2, {'can_commit': true});

    // Stop sharing with bob.
    await tester.tap(find.byKey(const ValueKey('repository.users.remove.$_bobId')));
    await tester.pumpAndSettle();
    expect(find.text('bob will lose access to this repository, and it is removed from their chats.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('repository.users.remove.confirm')));
    await _pumpUntil(tester, find.text('Stopped sharing.'));
    expect(server.requests.last.$1, '/api/v1/repositories/$_repositoryId/users/$_bobId/delete');
    await _pumpUntilGone(tester, find.text('bob'));
    await _settle(tester);
    expect(find.text('carol'), findsOneWidget);
    expect(find.text('dave'), findsOneWidget);
  });

  testWidgets('without write access, the switch is off and disabled, and a local repository has its own text', (tester) async {
    final server = await _FakeServer.start(
      tester,
      users: [fakeRepositoryUser(userId: _bobId, userName: 'bob')],
    );
    await _pumpCard(tester, server, allowCommits: false, local: true);
    await _pumpUntil(tester, find.text('bob'));
    await _settle(tester);
    expect(find.textContaining('cannot change or delete it.'), findsOneWidget);
    expect(find.text('Enable write access for the repository first'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('repository.users.canCommit.$_bobId'))).onChanged, isNull);
  });

  testWidgets('a repository shared with nobody says so', (tester) async {
    final server = await _FakeServer.start(tester, users: []);
    await _pumpCard(tester, server);
    await _pumpUntil(tester, find.text('Not shared with anyone'));
  });
}
