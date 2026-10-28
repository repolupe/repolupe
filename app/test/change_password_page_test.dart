import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/change_password_page.dart';
import 'package:app/pages/chat_page.dart';
import 'package:app/pages/home_page.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/persistence.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';

/// The `UserDto` JSON of the server's user.
Map<String, dynamic> _userJson({required bool mustChangePassword}) => {
  'id': _userId,
  'role': 'USER',
  'user_name': 'alice',
  'email': 'alice@example.com',
  'can_login': true,
  'can_manage_repositories': true,
  'can_change_identity': true,
  'must_change_password': mustChangePassword,
  'auto_commit': false,
  'created_at': '2026-10-20T12:00:00+00:00',
};

/// The `ErrorDto` JSON of the server.
Map<String, dynamic> _errorJson(String code, String message) => {'code': code, 'message': message};

/// Pumps until [finder] finds something, letting the requests to the server run meanwhile.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

/// A server (not the mocked actions of the other tests, since the session handling of `PASSWORD_CHANGE_REQUIRED` happens
/// below them) whose user must change their password while [mustChange] is set: then everything but `GET /me`,
/// `/login` and `/change-password` (with the current password `old`, which clears it) fails with
/// `PASSWORD_CHANGE_REQUIRED`.
class _FakeServer {
  final HttpServer server;
  bool mustChange;

  _FakeServer(this.server, {required this.mustChange}) {
    server.listen(_handle);
  }

  /// Bound and listened to in the real async zone, so that it also answers the requests sent outside the pumps.
  static Future<_FakeServer> start(WidgetTester tester, {required bool mustChange}) async {
    final fake = (await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      return _FakeServer(server, mustChange: mustChange);
    }))!;
    addTearDown(() => fake.server.close(force: true));
    return fake;
  }

  String get apiUrl => 'http://127.0.0.1:${server.port}';

  Future<void> _handle(HttpRequest request) async {
    final body = request.method == 'POST' ? jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic> : null;
    final response = request.response;
    response.headers.contentType = ContentType.json;
    switch ((request.method, request.uri.path)) {
      case ('GET', '/api/v1/me'):
        response.write(jsonEncode(_userJson(mustChangePassword: mustChange)));
      case ('POST', '/api/v1/login'):
        response.write(jsonEncode({'token': 'session-token', 'user': _userJson(mustChangePassword: mustChange)}));
      case ('POST', '/api/v1/change-password') when body!['current_password'] != 'old':
        response.statusCode = 422;
        response.write(jsonEncode(_errorJson('WRONG_PASSWORD', 'wrong')));
      case ('POST', '/api/v1/change-password'):
        mustChange = false;
        response.statusCode = 204;
      case _ when mustChange:
        response.statusCode = 403;
        response.write(jsonEncode(_errorJson('PASSWORD_CHANGE_REQUIRED', 'You must change your password first')));
      default:
        response.statusCode = 404;
        response.write(jsonEncode(_errorJson('NOT_FOUND', 'Not found')));
    }
    await response.close();
  }
}

Future<RefenaContainer> _container(WidgetTester tester, {Account? account}) async {
  final persistence = (await tester.runAsync(() => mockPersistence(account: account)))!;
  final container = RefenaContainer(overrides: [persistenceProvider.overrideWithValue(persistence)]);
  if (account != null) {
    container.redux(apiProvider).dispatch(ApiSetAccountAction(account));
  }
  return container;
}

Future<void> _pumpApp(WidgetTester tester, RefenaContainer container, Widget home) async {
  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          navigatorKey: container.read(navigationProvider).key,
          scaffoldMessengerKey: container.read(snackBarProvider).key,
          home: home,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('a user who must change their password sees only that page until they did', (tester) async {
    final server = await _FakeServer.start(tester, mustChange: true);
    final account = Account(
      apiUrl: server.apiUrl,
      token: 'session-token',
      user: AccountUser(id: _userId, userName: 'alice'),
    );
    final container = await _container(tester, account: account);
    await tester.runAsync(() => container.redux(meProvider).dispatchAsync(RefreshMeAction()));
    expect(container.read(meProvider)?.mustChangePassword, isTrue);

    await _pumpApp(tester, container, const HomePage());
    expect(find.byType(ChangePasswordPage), findsOneWidget);
    expect(find.byType(ChatPage), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('changePassword.current')), 'wrong');
    await tester.enterText(find.byKey(const ValueKey('changePassword.new')), 'new-password');
    await tester.enterText(find.byKey(const ValueKey('changePassword.confirm')), 'new-password');
    // The button is enabled once every field is filled.
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('changePassword.submit')));
    await _pumpUntil(tester, find.text('Current password is incorrect'));
    expect(find.byType(ChangePasswordPage), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('changePassword.current')), 'old');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('changePassword.submit')));
    await _pumpUntil(tester, find.byType(ChatPage));
    expect(find.byType(ChangePasswordPage), findsNothing);
    expect(container.read(meProvider)?.mustChangePassword, isFalse);
  });

  testWidgets('a request that fails with PASSWORD_CHANGE_REQUIRED opens the page, closing the others', (tester) async {
    final server = await _FakeServer.start(tester, mustChange: false);
    final account = Account(
      apiUrl: server.apiUrl,
      token: 'session-token',
      user: AccountUser(id: _userId, userName: 'alice'),
    );
    final container = await _container(tester, account: account);
    await tester.runAsync(() => container.redux(meProvider).dispatchAsync(RefreshMeAction()));

    await _pumpApp(tester, container, const HomePage());
    await _pumpUntil(tester, find.byType(ChatPage));
    // ignore: discarded_futures
    container.read(navigationProvider).key.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Somewhere'))));
    await tester.pumpAndSettle();
    expect(find.text('Somewhere'), findsOneWidget);

    // E.g. an admin required the change meanwhile.
    server.mustChange = true;
    await tester.runAsync(
      () => expectLater(
        container.redux(apiProvider).dispatchAsyncTakeResult(ApiListModelsAction()),
        throwsA(isA<ClientError_Api>()),
      ),
    );
    await _pumpUntil(tester, find.byType(ChangePasswordPage));
    await tester.pumpAndSettle();
    expect(find.text('Somewhere'), findsNothing);
    expect(find.byType(ChatPage), findsNothing);
  });

  testWidgets('a login that requires a password change opens the page instead of the chat', (tester) async {
    final server = await _FakeServer.start(tester, mustChange: true);
    final container = await _container(tester);
    await _pumpApp(tester, container, const Scaffold(body: Text('Setup')));

    await tester.runAsync(
      () => container.redux(accountProvider).dispatchAsync(LoginAction(apiUrl: server.apiUrl, userNameOrEmail: 'alice', password: 'old')),
    );
    await _pumpUntil(tester, find.byType(ChangePasswordPage));
    expect(container.read(meProvider)?.userName, 'alice');
    expect(find.byType(ChatPage), findsNothing);

    // Logging out is still possible.
    await tester.tap(find.byKey(const ValueKey('changePassword.logout')));
    await _pumpUntil(tester, find.text('Log in to your Repolupe server, or run Repolupe on this device.'));
    expect(container.read(accountProvider).accounts, isEmpty);
    expect(container.read(meProvider), isNull);
  });
}
