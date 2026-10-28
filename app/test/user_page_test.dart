import 'dart:async';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/user_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/widget/form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _adminId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _bobId = '0199a8d4-6d5e-7c3a-9b1f-000000000002';

/// The API of an admin and one other user, bob; the actions changing a user are recorded.
class _FakeApi {
  UserDto bob;
  final requests = <Object>[];

  /// The next deletion fails, e.g. to show the error in the dialog.
  bool failNextDelete = false;

  _FakeApi({required this.bob});

  /// Answers the actions of the page with this API.
  void answer(ApiMocks mock) {
    mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _adminId, userName: 'alice', role: UserRole.admin)));
    mock.on<ApiUpdateUserAction>((state, action) {
      requests.add(action);
      final request = action.request;
      bob = _withUser(
        bob,
        userName: request.userName,
        email: request.email,
        canLogin: request.canLogin,
        canManageRepositories: request.canManageRepositories,
        canChangeIdentity: request.canChangeIdentity,
        mustChangePassword: request.mustChangePassword,
      );
      return (state, bob);
    });
    mock.on<ApiResetPasswordAction>((state, action) {
      requests.add(action);
      bob = _withUser(
        bob,
        userName: bob.userName,
        email: bob.email,
        canLogin: bob.canLogin,
        canManageRepositories: bob.canManageRepositories,
        canChangeIdentity: bob.canChangeIdentity,
        mustChangePassword: action.request.mustChangePassword,
      );
      return (state, bob);
    });
    mock.on<ApiDeleteUserAction>((state, action) {
      requests.add(action);
      if (failNextDelete) {
        failNextDelete = false;
        throw apiError(ErrorCode.conflict, status: 409, message: 'Try again');
      }
      return state;
    });
  }
}

/// [user] with the fields an admin edits replaced.
UserDto _withUser(
  UserDto user, {
  required String userName,
  required String? email,
  required bool canLogin,
  required bool canManageRepositories,
  required bool canChangeIdentity,
  required bool mustChangePassword,
}) => UserDto(
  id: user.id,
  role: user.role,
  userName: userName,
  email: email,
  canLogin: canLogin,
  canManageRepositories: canManageRepositories,
  canChangeIdentity: canChangeIdentity,
  mustChangePassword: mustChangePassword,
  defaultModelId: user.defaultModelId,
  locale: user.locale,
  autoCommit: user.autoCommit,
  fullName: user.fullName,
  firstName: user.firstName,
  about: user.about,
  createdAt: user.createdAt,
);

/// Opens the page of [user] above a list page for the admin of [api], whose user is loaded.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeApi api, {required UserDto user}) async {
  // Tall enough for the whole page of a user, so that its lower cards are built too.
  tester.view.physicalSize = const Size(600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: _adminId),
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
  unawaited(container.global.dispatchAsync(NavigateAction.push(UserPage(user: user))));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('an admin edits another user, sets their password and deletes them', (tester) async {
    final api = _FakeApi(
      bob: fakeUser(id: _bobId, userName: 'bob', email: 'bob@example.com'),
    );
    final container = await _pumpPage(tester, api, user: api.bob);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();

    expect(find.text('bob@example.com'), findsOneWidget);
    expect(find.text('Allowed'), findsOneWidget);
    expect(find.text('Can manage their own and share them'), findsOneWidget);
    expect(find.text('Login disabled'), findsNothing);

    // Leaving the form: at once without changes, after asking with them.
    await tester.tap(find.byKey(const ValueKey('user.edit')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('userForm.save')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('user.edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('userForm.userName')), 'bob-draft');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unsavedChanges.keepEditing')));
    await tester.pumpAndSettle();
    expect(find.text('bob-draft'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('unsavedChanges.discard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('userForm.save')), findsNothing);
    expect(find.text('bob-draft'), findsNothing);
    expect(api.requests, isEmpty);

    // Edit: the switches of a user can be turned off, the email removed.
    await tester.tap(find.byKey(const ValueKey('user.edit')));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('userForm.canLogin'))).onChanged, isNotNull);
    await tester.tap(find.byKey(const ValueKey('userForm.canLogin')));
    await tester.tap(find.byKey(const ValueKey('userForm.canManageRepositories')));
    await tester.tap(find.byKey(const ValueKey('userForm.mustChangePassword')));
    await tester.enterText(find.byKey(const ValueKey('userForm.userName')), 'bob2');
    await tester.enterText(find.byKey(const ValueKey('userForm.email')), '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('userForm.save')));
    await tester.pump();
    expect(find.text('User updated.'), findsWidgets);
    final update = api.requests.last as ApiUpdateUserAction;
    expect(update.id, UuidValue.fromString(_bobId));
    expect(
      update.request,
      const UpdateUserRequest(
        userName: 'bob2',
        email: null,
        canLogin: false,
        canManageRepositories: false,
        canChangeIdentity: true,
        mustChangePassword: true,
      ),
    );
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('user.password.save')));
    await tester.pump();
    expect(find.descendant(of: find.byType(FormSheet), matching: find.text('Missing password')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(api.requests.length, 1);
    await tester.enterText(find.byKey(const ValueKey('user.password.new')), 'new-password');
    await tester.tap(find.byKey(const ValueKey('user.password.mustChange')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('user.password.save')));
    await tester.pump();
    expect(find.text('Password set.'), findsWidgets);
    final reset = api.requests.last as ApiResetPasswordAction;
    expect(reset.id, UuidValue.fromString(_bobId));
    expect(reset.request, const ResetPasswordRequest(password: 'new-password', mustChangePassword: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user.password.save')), findsNothing);
    expect(find.text('Must be changed at the next login'), findsNothing);
    clearSnackBars();

    // Delete, after typing the (new) user name.
    await tester.tap(find.byKey(const ValueKey('user.delete')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('user.delete.confirm'));
    expect(tester.widget<FilledButton>(confirm).enabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('user.delete.verification')), 'bob');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).enabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('user.delete.verification')), 'bob2');
    await tester.pump();
    // A failure is shown in the dialog, which stays open for another try.
    api.failNextDelete = true;
    await tester.tap(confirm);
    await tester.pump();
    expect(find.byKey(const ValueKey('user.delete.error')), findsOneWidget);
    expect(find.text('Could not delete the user: It was changed at the same time, please try again.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(confirm);
    await tester.pump();
    expect(find.text('User deleted.'), findsWidgets);
    expect((api.requests.last as ApiDeleteUserAction).id, UuidValue.fromString(_bobId));
    await tester.pumpAndSettle();
    expect(find.text('the list'), findsOneWidget);
    expect(find.byKey(const ValueKey('user.body')), findsNothing);
  });

  testWidgets("the admin's own page offers neither the password nor deleting, and cannot restrict them", (tester) async {
    final api = _FakeApi(
      bob: fakeUser(id: _bobId, userName: 'bob'),
    );
    await _pumpPage(
      tester,
      api,
      user: fakeUser(id: _adminId, userName: 'alice', role: UserRole.admin),
    );

    expect(find.text('Admin'), findsNWidgets(2));
    expect(find.text('Change your own password in your account settings'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('user.setPassword'))).enabled, isFalse);
    expect(find.text('You cannot delete yourself'), findsOneWidget);
    expect(find.byKey(const ValueKey('user.delete')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('user.edit')));
    await tester.pumpAndSettle();
    for (final key in ['userForm.canLogin', 'userForm.canManageRepositories', 'userForm.canChangeIdentity']) {
      expect(tester.widget<SwitchListTile>(find.byKey(ValueKey(key))).onChanged, isNull, reason: key);
    }
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('userForm.mustChangePassword'))).onChanged, isNotNull);
    expect(find.text('Admins cannot be restricted'), findsNWidgets(3));
  });
}
