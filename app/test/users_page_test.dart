import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/settings/admin/user_page.dart';
import 'package:app/pages/settings/admin/users_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/fake_user.dart';
import 'support/persistence.dart';
import 'support/rust.dart';

const _adminId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _bobId = '0199a8d4-6d5e-7c3a-9b1f-000000000002';
const _carolId = '0199a8d4-6d5e-7c3a-9b1f-000000000003';

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

/// A server with an admin and the users; the POSTs are recorded by their path with their body.
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
      case ('GET', '/api/v1/me'):
        response.write(jsonEncode(users.first));
      case ('GET', '/api/v1/users'):
        response.write(jsonEncode(users));
      case ('POST', '/api/v1/register') when users.any((u) => u['user_name'] == body!['user_name']):
        response.statusCode = 409;
        response.write(jsonEncode(fakeError('USER_NAME_TAKEN', 'taken')));
      case ('POST', '/api/v1/register'):
        final user = fakeUser(
          id: _carolId,
          userName: body!['user_name'] as String,
          email: body['email'] as String?,
          mustChangePassword: body['must_change_password'] as bool,
        );
        users = [...users, user];
        response.statusCode = 201;
        response.write(jsonEncode(user));
      default:
        response.statusCode = 404;
        response.write(jsonEncode(fakeError('NOT_FOUND', 'Not found')));
    }
    await response.close();
  }
}

/// Opens the page for the admin of [server], whose user is loaded. With [local], the active account is the local
/// instance's, while the requests still go to [server].
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeServer server, {bool local = false}) async {
  // Tall enough for the whole page of a user, so that its lower cards are built too.
  tester.view.physicalSize = const Size(600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final account = Account(
    apiUrl: server.apiUrl,
    token: 'session-token',
    user: AccountUser(id: _adminId, userName: 'alice'),
  );
  final stored = local ? account.copyWith(apiUrl: null) : account;
  final persistence = (await tester.runAsync(() => mockPersistence(account: stored)))!;
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
          home: const UsersPage(),
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

  testWidgets('the users page lists, filters and opens a user, and creates one', (tester) async {
    final server = await _FakeServer.start(
      tester,
      users: [
        fakeUser(id: _adminId, userName: 'alice', role: 'ADMIN'),
        fakeUser(
          id: _bobId,
          userName: 'bob',
          email: 'bob@example.com',
          fullName: 'Bob Builder',
          canLogin: false,
          canManageRepositories: false,
          mustChangePassword: true,
        ),
      ],
    );
    final container = await _pumpPage(tester, server);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();

    await _pumpUntil(tester, find.text('2 Users'));
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('bob@example.com'), findsOneWidget);
    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('Login disabled'), findsOneWidget);
    expect(find.text('Password change required'), findsOneWidget);
    expect(find.text('Repositories read only'), findsOneWidget);
    expect(find.text('Fixed user name and email'), findsNothing);

    // Filtered by the full name, then nothing matches.
    await tester.enterText(find.byKey(const ValueKey('users.search')), 'builder');
    await tester.pump();
    expect(find.byKey(const ValueKey('users.$_bobId')), findsOneWidget);
    expect(find.byKey(const ValueKey('users.$_adminId')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('users.search')), 'zzz');
    await tester.pump();
    expect(find.text('No users match your search.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('users.search')), '');
    await tester.pump();

    // Opens the user's page, which offers everything for another user.
    await tester.tap(find.byKey(const ValueKey('users.$_bobId')));
    await _settle(tester);
    expect(find.byType(UserPage), findsOneWidget);
    expect(find.text('Sets a new password for bob and signs them out everywhere.'), findsOneWidget);
    expect(find.text('Disabled (signed out everywhere)'), findsOneWidget);
    expect(find.text('Must be changed at the next login'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('user.setPassword'))).enabled, isTrue);
    expect(find.byKey(const ValueKey('user.delete')), findsOneWidget);
    await tester.pageBack();
    await _settle(tester);
    expect(find.byType(UsersPage), findsOneWidget);

    // Creates a user: the password is checked first, then the server rejects the taken user name.
    await tester.tap(find.byKey(const ValueKey('users.new')));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('userForm.userName')), 'bob');
    await tester.enterText(find.byKey(const ValueKey('userForm.password')), 'short');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('userForm.save')));
    await _pumpUntil(tester, find.text('Password must be 8 to 128 characters long'));
    expect(server.requests, isEmpty);
    clearSnackBars();
    await tester.enterText(find.byKey(const ValueKey('userForm.password')), 'secret-password');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('userForm.save')));
    await _pumpUntil(tester, find.text('A user with this user name already exists'));
    expect(find.byKey(const ValueKey('userForm.save')), findsOneWidget);
    clearSnackBars();
    await tester.enterText(find.byKey(const ValueKey('userForm.userName')), 'carol');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('userForm.save')));
    await _pumpUntil(tester, find.text('User created.'));
    expect(server.requests.last.$1, '/api/v1/register');
    expect(server.requests.last.$2, {
      'user_name': 'carol',
      'email': null,
      'password': 'secret-password',
      'must_change_password': true,
    });
    await _settle(tester);
    expect(find.byKey(const ValueKey('userForm.save')), findsNothing);
    await _pumpUntil(tester, find.text('3 Users'));
    expect(find.text('carol'), findsOneWidget);
  });

  testWidgets('the users page of the local instance offers no new user', (tester) async {
    final server = await _FakeServer.start(
      tester,
      users: [fakeUser(id: _adminId, userName: 'admin', role: 'ADMIN')],
    );
    await _pumpPage(tester, server, local: true);

    await _pumpUntil(tester, find.text('1 User'));
    expect(find.text('admin'), findsOneWidget);
    expect(
      find.text(
        'Repolupe on this device has only one user, so no users can be added. To share chats and repositories with others, use a Repolupe server.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('users.new')), findsNothing);
  });
}
