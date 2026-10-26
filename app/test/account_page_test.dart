import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/settings/account_page.dart';
import 'package:app/pages/settings_page.dart';
import 'package:app/service/account_service.dart';
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

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';

/// Pumps until [finder] finds something, letting the requests to the server run meanwhile.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the account page changes the user name and email, and the password', (tester) async {
    var userName = 'alice';
    String? email = 'alice@example.com';
    // Bound and listened to in the real async zone, so that it also answers the requests sent outside the pumps.
    final server = (await tester.runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0)))!;
    addTearDown(() => server.close(force: true));
    await tester.runAsync(() async {
      server.listen((request) async {
        final body = request.method == 'POST' ? jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic> : null;
        final response = request.response;
        response.headers.contentType = ContentType.json;
        switch ((request.method, request.uri.path)) {
          case ('GET', '/api/v1/me'):
            response.write(jsonEncode(fakeUser(id: _userId, userName: userName, email: email)));
          case ('POST', '/api/v1/me/identity') when body!['user_name'] == 'bob':
            response.statusCode = 409;
            response.write(jsonEncode(fakeError('USER_NAME_TAKEN', 'taken')));
          case ('POST', '/api/v1/me/identity'):
            userName = body!['user_name'] as String;
            email = body['email'] as String?;
            response.write(jsonEncode(fakeUser(id: _userId, userName: userName, email: email)));
          case ('POST', '/api/v1/change-password') when body!['current_password'] != 'right':
            response.statusCode = 422;
            response.write(jsonEncode(fakeError('WRONG_PASSWORD', 'wrong')));
          case ('POST', '/api/v1/change-password'):
            response.statusCode = 204;
          default:
            response.statusCode = 404;
            response.write(jsonEncode(fakeError('NOT_FOUND', 'Not found')));
        }
        await response.close();
      });
    });

    final account = Account(
      apiUrl: 'http://127.0.0.1:${server.port}',
      token: 'session-token',
      user: AccountUser(id: _userId, userName: 'alice'),
    );
    final persistence = (await tester.runAsync(() => mockPersistence(account: account)))!;
    final container = RefenaContainer(overrides: [persistenceProvider.overrideWithValue(persistence)]);
    container.redux(apiProvider).dispatch(ApiSetAccountAction(account));
    await tester.runAsync(() => container.redux(meProvider).dispatchAsync(RefreshMeAction()));
    expect(container.read(meProvider)?.userName, 'alice');

    await tester.pumpWidget(
      RefenaScope.withContainer(
        container: container,
        child: TranslationProvider(
          child: MaterialApp(
            navigatorKey: container.read(navigationProvider).key,
            scaffoldMessengerKey: container.read(snackBarProvider).key,
            home: const SettingsPage(),
          ),
        ),
      ),
    );
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();

    // The hub: no administration for a user, the account section opens its page.
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings.account')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountPage), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);

    // A taken user name keeps the dialog open and is shown in it, since a snack bar would be behind its barrier.
    await tester.tap(find.byKey(const ValueKey('account.userName')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('account.userNameDialog.userName')), 'bob');
    await tester.tap(find.byKey(const ValueKey('account.userNameDialog.save')));
    await _pumpUntil(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('A user with this user name already exists')));
    expect(find.byKey(const ValueKey('account.userNameDialog.save')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    // Saved: shown by the page and stored with the account, keeping the email.
    await tester.enterText(find.byKey(const ValueKey('account.userNameDialog.userName')), 'alice2');
    await tester.tap(find.byKey(const ValueKey('account.userNameDialog.save')));
    await _pumpUntil(tester, find.text('User name saved'));
    await tester.pumpAndSettle();
    clearSnackBars();
    expect(find.byKey(const ValueKey('account.userNameDialog.save')), findsNothing);
    expect(find.text('alice2'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);

    // The email on its own, keeping the user name.
    await tester.tap(find.byKey(const ValueKey('account.email')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('account.emailDialog.email')), 'alice2@example.com');
    await tester.tap(find.byKey(const ValueKey('account.emailDialog.save')));
    await _pumpUntil(tester, find.text('Email saved'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account.emailDialog.save')), findsNothing);
    expect(find.text('alice2'), findsOneWidget);
    expect(find.text('alice2@example.com'), findsOneWidget);
    expect(container.read(accountProvider).active?.user.userName, 'alice2');
    expect(persistence.getAccounts().single.user.userName, 'alice2');
    clearSnackBars();

    // The password: checked before it is sent, then the current one by the server.
    await tester.tap(find.byKey(const ValueKey('account.password')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('account.password.current')), 'wrong');
    await tester.enterText(find.byKey(const ValueKey('account.password.new')), 'new-password');
    await tester.enterText(find.byKey(const ValueKey('account.password.confirm')), 'other-password');
    await tester.tap(find.byKey(const ValueKey('account.password.save')));
    await _pumpUntil(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('New passwords do not match.')));
    await tester.enterText(find.byKey(const ValueKey('account.password.confirm')), 'new-password');
    await tester.tap(find.byKey(const ValueKey('account.password.save')));
    await _pumpUntil(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Current password is incorrect')));
    expect(find.text('New passwords do not match.'), findsNothing);
    expect(find.byKey(const ValueKey('account.password.save')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('account.password.current')), 'right');
    await tester.tap(find.byKey(const ValueKey('account.password.save')));
    await _pumpUntil(tester, find.text('Password changed. Your other sessions were signed out.'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account.password.save')), findsNothing);
  });
}
