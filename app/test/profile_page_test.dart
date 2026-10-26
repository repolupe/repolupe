import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/settings/profile_page.dart';
import 'package:app/pages/settings_page.dart';
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

  testWidgets('the profile page sets and clears each field of the profile', (tester) async {
    String? fullName;
    String? firstName;
    String? about;
    final profileRequests = <Map<String, dynamic>>[];
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
            response.write(jsonEncode(fakeUser(id: _userId, fullName: fullName, firstName: firstName, about: about)));
          case ('POST', '/api/v1/me/profile'):
            profileRequests.add(body!);
            fullName = body['full_name'] as String?;
            firstName = body['first_name'] as String?;
            about = body['about'] as String?;
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

    // The hub opens the page, which shows the empty profile.
    await tester.tap(find.byKey(const ValueKey('settings.profile')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.text('-'), findsNWidgets(3));

    // Too long: checked before it is sent.
    await tester.tap(find.byKey(const ValueKey('profile.fullName')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('profile.fullNameDialog.fullName')), 'a' * 101);
    await tester.tap(find.byKey(const ValueKey('profile.fullNameDialog.save')));
    await _pumpUntil(tester, find.text('Full name must be at most 100 characters long.'));
    expect(profileRequests, isEmpty);
    expect(find.byKey(const ValueKey('profile.fullNameDialog.save')), findsOneWidget);
    clearSnackBars();

    // Saved trimmed, the page shows the new full name.
    await tester.enterText(find.byKey(const ValueKey('profile.fullNameDialog.fullName')), ' Ada Lovelace ');
    await tester.tap(find.byKey(const ValueKey('profile.fullNameDialog.save')));
    await _pumpUntil(tester, find.text('Full name saved'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile.fullNameDialog.save')), findsNothing);
    expect(profileRequests.single, {'full_name': 'Ada Lovelace', 'first_name': null, 'about': null});
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(container.read(meProvider)?.fullName, 'Ada Lovelace');
    clearSnackBars();

    // Each dialog keeps the other fields.
    await tester.tap(find.byKey(const ValueKey('profile.firstName')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('profile.firstNameDialog.firstName')), 'Ada');
    await tester.tap(find.byKey(const ValueKey('profile.firstNameDialog.save')));
    await _pumpUntil(tester, find.text('First name saved'));
    await tester.pumpAndSettle();
    expect(profileRequests.last, {'full_name': 'Ada Lovelace', 'first_name': 'Ada', 'about': null});
    clearSnackBars();

    await tester.tap(find.byKey(const ValueKey('profile.about')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile.aboutDialog.about')),
      'Likes short answers.\nWorks on engines.',
    );
    await tester.tap(find.byKey(const ValueKey('profile.aboutDialog.save')));
    await _pumpUntil(tester, find.text('About saved'));
    await tester.pumpAndSettle();
    expect(profileRequests.last, {
      'full_name': 'Ada Lovelace',
      'first_name': 'Ada',
      'about': 'Likes short answers.\nWorks on engines.',
    });
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Likes short answers.\nWorks on engines.'), findsOneWidget);
    clearSnackBars();

    // Cleared: an empty field is sent as null.
    await tester.tap(find.byKey(const ValueKey('profile.about')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('profile.aboutDialog.about')), '  ');
    await tester.tap(find.byKey(const ValueKey('profile.aboutDialog.save')));
    await _pumpUntil(tester, find.text('About saved'));
    await tester.pumpAndSettle();
    expect(profileRequests.last, {'full_name': 'Ada Lovelace', 'first_name': 'Ada', 'about': null});
    expect(find.text('-'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
  });
}
