import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/settings/admin/user_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/fake_user.dart';
import 'support/persistence.dart';
import 'support/rust.dart';

const _adminId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _bobId = '0199a8d4-6d5e-7c3a-9b1f-000000000002';

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

/// A server with an admin and one other user, bob; the POSTs are recorded by their path with their body.
class _FakeServer {
  final HttpServer server;
  Map<String, dynamic> bob;
  final requests = <(String, Map<String, dynamic>?)>[];

  /// The next deletion fails, e.g. to show the error in the dialog.
  bool failNextDelete = false;

  _FakeServer(this.server, {required this.bob}) {
    server.listen(_handle);
  }

  static Future<_FakeServer> start(WidgetTester tester, {required Map<String, dynamic> bob}) async {
    final fake = (await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      return _FakeServer(server, bob: bob);
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
        response.write(jsonEncode(fakeUser(id: _adminId, userName: 'alice', role: 'ADMIN')));
      case ('POST', '/api/v1/users/$_bobId/update'):
        bob = {
          ...bob,
          'user_name': body!['user_name'],
          'email': body['email'],
          'can_login': body['can_login'],
          'can_manage_repositories': body['can_manage_repositories'],
          'can_change_identity': body['can_change_identity'],
          'must_change_password': body['must_change_password'],
        };
        response.write(jsonEncode(bob));
      case ('POST', '/api/v1/users/$_bobId/password'):
        bob = {...bob, 'must_change_password': body!['must_change_password']};
        response.write(jsonEncode(bob));
      case ('POST', '/api/v1/delete-user') when failNextDelete:
        failNextDelete = false;
        response.statusCode = 409;
        response.write(jsonEncode(fakeError('CONFLICT', 'Try again')));
      case ('POST', '/api/v1/delete-user') when body!['user_id'] == _bobId:
        response.statusCode = 204;
      default:
        response.statusCode = 404;
        response.write(jsonEncode(fakeError('NOT_FOUND', 'Not found')));
    }
    await response.close();
  }
}

/// Opens the page of [user] above a list page for the admin of [server], whose user is loaded.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeServer server, {required UserDto user}) async {
  // Tall enough for the whole page of a user, so that its lower cards are built too.
  tester.view.physicalSize = const Size(600, 2400);
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
          home: const Scaffold(body: Text('the list')),
        ),
      ),
    ),
  );
  unawaited(container.global.dispatchAsync(NavigateAction.push(UserPage(user: user))));
  await _settle(tester);
  return container;
}

/// The `UserDto` of the fake JSON, as the list page passes it to the page.
UserDto _user(Map<String, dynamic> json) => UserDto(
  id: UuidValue.fromString(json['id'] as String),
  role: json['role'] == 'ADMIN' ? UserRole.admin : UserRole.user,
  userName: json['user_name'] as String,
  email: json['email'] as String?,
  canLogin: json['can_login'] as bool,
  canManageRepositories: json['can_manage_repositories'] as bool,
  canChangeIdentity: json['can_change_identity'] as bool,
  mustChangePassword: json['must_change_password'] as bool,
  autoCommit: json['auto_commit'] as bool,
  fullName: json['full_name'] as String?,
  createdAt: DateTime.parse(json['created_at'] as String),
);

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('an admin edits another user, sets their password and deletes them', (tester) async {
    final server = await _FakeServer.start(
      tester,
      bob: fakeUser(id: _bobId, userName: 'bob', email: 'bob@example.com'),
    );
    final container = await _pumpPage(tester, server, user: _user(server.bob));
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();

    expect(find.text('bob@example.com'), findsOneWidget);
    expect(find.text('Allowed'), findsOneWidget);
    expect(find.text('Can manage their own and share them'), findsOneWidget);
    expect(find.text('Login disabled'), findsNothing);

    // Leaving the form: at once without changes, after asking with them.
    await tester.tap(find.byKey(const ValueKey('user.edit')));
    await _settle(tester);
    await tester.pageBack();
    await _settle(tester);
    expect(find.byKey(const ValueKey('userForm.save')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('user.edit')));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('userForm.userName')), 'bob-draft');
    await tester.pump();
    await tester.pageBack();
    await _settle(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unsavedChanges.keepEditing')));
    await _settle(tester);
    expect(find.text('bob-draft'), findsOneWidget);
    await tester.pageBack();
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('unsavedChanges.discard')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('userForm.save')), findsNothing);
    expect(find.text('bob-draft'), findsNothing);
    expect(server.requests, isEmpty);

    // Edit: the switches of a user can be turned off, the email removed.
    await tester.tap(find.byKey(const ValueKey('user.edit')));
    await _settle(tester);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('userForm.canLogin'))).onChanged, isNotNull);
    await tester.tap(find.byKey(const ValueKey('userForm.canLogin')));
    await tester.tap(find.byKey(const ValueKey('userForm.canManageRepositories')));
    await tester.tap(find.byKey(const ValueKey('userForm.mustChangePassword')));
    await tester.enterText(find.byKey(const ValueKey('userForm.userName')), 'bob2');
    await tester.enterText(find.byKey(const ValueKey('userForm.email')), '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('userForm.save')));
    await _pumpUntil(tester, find.text('User updated.'));
    expect(server.requests.last.$1, '/api/v1/users/$_bobId/update');
    expect(server.requests.last.$2, {
      'user_name': 'bob2',
      'email': null,
      'can_login': false,
      'can_manage_repositories': false,
      'can_change_identity': true,
      'must_change_password': true,
    });
    await _settle(tester);
    expect(find.byKey(const ValueKey('userForm.save')), findsNothing);
    // The app bar and the row.
    expect(find.text('bob2'), findsNWidgets(2));
    expect(find.text('bob@example.com'), findsNothing);
    expect(find.text('Disabled (signed out everywhere)'), findsOneWidget);
    expect(find.text('Login disabled'), findsOneWidget);
    expect(find.text('Repositories read only'), findsOneWidget);
    expect(find.text('Must be changed at the next login'), findsOneWidget);
    clearSnackBars();

    // Set the password: checked first, then sent with the switch turned off.
    await tester.tap(find.byKey(const ValueKey('user.setPassword')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('user.password.save')));
    await _pumpUntil(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Missing password')));
    expect(find.byType(SnackBar), findsNothing);
    expect(server.requests.length, 1);
    await tester.enterText(find.byKey(const ValueKey('user.password.new')), 'new-password');
    await tester.tap(find.byKey(const ValueKey('user.password.mustChange')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('user.password.save')));
    await _pumpUntil(tester, find.text('Password set.'));
    expect(server.requests.last.$1, '/api/v1/users/$_bobId/password');
    expect(server.requests.last.$2, {'password': 'new-password', 'must_change_password': false});
    await _settle(tester);
    expect(find.byKey(const ValueKey('user.password.save')), findsNothing);
    expect(find.text('Must be changed at the next login'), findsNothing);
    clearSnackBars();

    // Delete, after typing the (new) user name.
    await tester.tap(find.byKey(const ValueKey('user.delete')));
    await _settle(tester);
    final confirm = find.byKey(const ValueKey('user.delete.confirm'));
    expect(tester.widget<FilledButton>(confirm).enabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('user.delete.verification')), 'bob');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).enabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('user.delete.verification')), 'bob2');
    await tester.pump();
    // A failure is shown in the dialog, which stays open for another try.
    server.failNextDelete = true;
    await tester.tap(confirm);
    await _pumpUntil(tester, find.byKey(const ValueKey('user.delete.error')));
    expect(find.text('Could not delete the user: It was changed at the same time, please try again.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(confirm);
    await _pumpUntil(tester, find.text('User deleted.'));
    expect(server.requests.last.$1, '/api/v1/delete-user');
    expect(server.requests.last.$2, {'user_id': _bobId});
    await _settle(tester);
    expect(find.text('the list'), findsOneWidget);
    expect(find.byKey(const ValueKey('user.body')), findsNothing);
  });

  testWidgets("the admin's own page offers neither the password nor deleting, and cannot restrict them", (tester) async {
    final server = await _FakeServer.start(
      tester,
      bob: fakeUser(id: _bobId, userName: 'bob'),
    );
    await _pumpPage(
      tester,
      server,
      user: _user(fakeUser(id: _adminId, userName: 'alice', role: 'ADMIN')),
    );

    expect(find.text('Admin'), findsNWidgets(2));
    expect(find.text('Change your own password in your account settings'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('user.setPassword'))).enabled, isFalse);
    expect(find.text('You cannot delete yourself'), findsOneWidget);
    expect(find.byKey(const ValueKey('user.delete')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('user.edit')));
    await _settle(tester);
    for (final key in ['userForm.canLogin', 'userForm.canManageRepositories', 'userForm.canChangeIdentity']) {
      expect(tester.widget<SwitchListTile>(find.byKey(ValueKey(key))).onChanged, isNull, reason: key);
    }
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('userForm.mustChangePassword'))).onChanged, isNotNull);
    expect(find.text('Admins cannot be restricted'), findsNWidgets(3));
  });
}
