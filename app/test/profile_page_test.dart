import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/profile_page.dart';
import 'package:app/pages/settings_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/api.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';

/// The fields of [action], to compare it in one go.
({String? fullName, String? firstName, String? about}) _fields(ApiUpdateProfileAction action) =>
    (fullName: action.fullName, firstName: action.firstName, about: action.about);

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the profile page sets and clears each field of the profile', (tester) async {
    String? fullName;
    String? firstName;
    String? about;
    final profileRequests = <ApiUpdateProfileAction>[];
    final container = (await tester.runAsync(
      () => mockContainer(
        account: fakeAccount(userId: _userId),
        api: (mock) {
          mock.on<ApiGetMeAction>(
            (state, _) => (state, fakeUser(id: _userId, fullName: fullName, firstName: firstName, about: about)),
          );
          mock.on<ApiUpdateProfileAction>((state, action) {
            profileRequests.add(action);
            fullName = action.fullName;
            firstName = action.firstName;
            about = action.about;
            return state;
          });
        },
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
    await tester.pumpAndSettle();
    expect(find.text('Full name must be at most 100 characters long.'), findsWidgets);
    expect(profileRequests, isEmpty);
    expect(find.byKey(const ValueKey('profile.fullNameDialog.save')), findsOneWidget);
    clearSnackBars();

    // Saved trimmed, the page shows the new full name.
    await tester.enterText(find.byKey(const ValueKey('profile.fullNameDialog.fullName')), ' Ada Lovelace ');
    await tester.tap(find.byKey(const ValueKey('profile.fullNameDialog.save')));
    await tester.pumpAndSettle();
    expect(find.text('Full name saved'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile.fullNameDialog.save')), findsNothing);
    expect(profileRequests.map(_fields), [(fullName: 'Ada Lovelace', firstName: null, about: null)]);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(container.read(meProvider)?.fullName, 'Ada Lovelace');
    clearSnackBars();

    // Each dialog keeps the other fields.
    await tester.tap(find.byKey(const ValueKey('profile.firstName')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('profile.firstNameDialog.firstName')), 'Ada');
    await tester.tap(find.byKey(const ValueKey('profile.firstNameDialog.save')));
    await tester.pumpAndSettle();
    expect(find.text('First name saved'), findsOneWidget);
    expect(_fields(profileRequests.last), (fullName: 'Ada Lovelace', firstName: 'Ada', about: null));
    clearSnackBars();

    await tester.tap(find.byKey(const ValueKey('profile.about')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile.aboutDialog.about')),
      'Likes short answers.\nWorks on engines.',
    );
    await tester.tap(find.byKey(const ValueKey('profile.aboutDialog.save')));
    await tester.pumpAndSettle();
    expect(find.text('About saved'), findsOneWidget);
    expect(
      _fields(profileRequests.last),
      (fullName: 'Ada Lovelace', firstName: 'Ada', about: 'Likes short answers.\nWorks on engines.'),
    );
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Likes short answers.\nWorks on engines.'), findsOneWidget);
    clearSnackBars();

    // Cleared: an empty field is sent as null.
    await tester.tap(find.byKey(const ValueKey('profile.about')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('profile.aboutDialog.about')), '  ');
    await tester.tap(find.byKey(const ValueKey('profile.aboutDialog.save')));
    await tester.pumpAndSettle();
    expect(find.text('About saved'), findsOneWidget);
    expect(_fields(profileRequests.last), (fullName: 'Ada Lovelace', firstName: 'Ada', about: null));
    expect(find.text('-'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
  });
}
