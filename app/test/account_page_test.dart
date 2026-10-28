import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/account_page.dart';
import 'package:app/pages/settings_page.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/widget/form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/api.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the account page changes the user name and email, and the password', (tester) async {
    var userName = 'alice';
    String? email = 'alice@example.com';
    final container = (await tester.runAsync(
      () => mockContainer(
        account: fakeAccount(userId: _userId),
        api: (mock) {
          mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _userId, userName: userName, email: email)));
          mock.on<ApiUpdateIdentityAction>((state, action) {
            if (action.userName == 'bob') {
              throw apiError(ErrorCode.userNameTaken, status: 409);
            }
            userName = action.userName;
            email = action.email;
            return (state, fakeUser(id: _userId, userName: userName, email: email));
          });
          mock.on<ApiChangePasswordAction>((state, action) {
            if (action.currentPassword != 'right') {
              throw apiError(ErrorCode.wrongPassword, status: 422);
            }
            return state;
          });
        },
      ),
    ))!;
    await container.redux(meProvider).dispatchAsync(RefreshMeAction());
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
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(FormSheet), matching: find.text('A user with this user name already exists')), findsOneWidget);
    expect(find.byKey(const ValueKey('account.userNameDialog.save')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    // Saved: shown by the page and stored with the account, keeping the email.
    await tester.enterText(find.byKey(const ValueKey('account.userNameDialog.userName')), 'alice2');
    await tester.tap(find.byKey(const ValueKey('account.userNameDialog.save')));
    await tester.pumpAndSettle();
    expect(find.text('User name saved'), findsOneWidget);
    clearSnackBars();
    expect(find.byKey(const ValueKey('account.userNameDialog.save')), findsNothing);
    expect(find.text('alice2'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);

    // The email on its own, keeping the user name.
    await tester.tap(find.byKey(const ValueKey('account.email')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('account.emailDialog.email')), 'alice2@example.com');
    await tester.tap(find.byKey(const ValueKey('account.emailDialog.save')));
    await tester.pumpAndSettle();
    expect(find.text('Email saved'), findsOneWidget);
    expect(find.byKey(const ValueKey('account.emailDialog.save')), findsNothing);
    expect(find.text('alice2'), findsOneWidget);
    expect(find.text('alice2@example.com'), findsOneWidget);
    expect(container.read(accountProvider).active?.user.userName, 'alice2');
    expect(container.read(persistenceProvider).getAccounts().single.user.userName, 'alice2');
    clearSnackBars();

    // The password: checked before it is sent, then the current one by the server.
    await tester.tap(find.byKey(const ValueKey('account.password')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('account.password.current')), 'wrong');
    await tester.enterText(find.byKey(const ValueKey('account.password.new')), 'new-password');
    await tester.enterText(find.byKey(const ValueKey('account.password.confirm')), 'other-password');
    await tester.tap(find.byKey(const ValueKey('account.password.save')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(FormSheet), matching: find.text('New passwords do not match.')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('account.password.confirm')), 'new-password');
    await tester.tap(find.byKey(const ValueKey('account.password.save')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(FormSheet), matching: find.text('Current password is incorrect')), findsOneWidget);
    expect(find.text('New passwords do not match.'), findsNothing);
    expect(find.byKey(const ValueKey('account.password.save')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('account.password.current')), 'right');
    await tester.tap(find.byKey(const ValueKey('account.password.save')));
    await tester.pumpAndSettle();
    expect(find.text('Password changed. Your other sessions were signed out.'), findsOneWidget);
    expect(find.byKey(const ValueKey('account.password.save')), findsNothing);
  });
}
