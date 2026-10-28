import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/user_page.dart';
import 'package:app/pages/settings/admin/users_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/api.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _adminId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _bobId = '0199a8d4-6d5e-7c3a-9b1f-000000000002';
const _carolId = '0199a8d4-6d5e-7c3a-9b1f-000000000003';

/// The API of an admin (the first of [users]) and the users; the registrations are recorded by their request.
class _FakeApi {
  List<UserDto> users;
  final registers = <RegisterRequest>[];

  _FakeApi({required this.users});

  /// Answers the actions of the page with this API.
  void answer(ApiMocks mock) {
    mock.on<ApiGetMeAction>((state, _) => (state, users.first));
    mock.on<ApiListUsersAction>((state, _) => (state, users));
    mock.on<ApiRegisterUserAction>((state, action) {
      final request = action.request;
      registers.add(request);
      if (users.any((u) => u.userName == request.userName)) {
        throw apiError(ErrorCode.userNameTaken, status: 409, message: 'taken');
      }
      final user = fakeUser(id: _carolId, userName: request.userName, email: request.email, mustChangePassword: request.mustChangePassword);
      users = [...users, user];
      return (state, user);
    });
  }
}

/// Opens the page for the admin of [api], whose user is loaded. With [local], the active account is the local
/// instance's, while the actions are answered by [api] all the same.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeApi api, {bool local = false}) async {
  // Tall enough for the whole page of a user, so that its lower cards are built too.
  tester.view.physicalSize = const Size(600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final account = fakeAccount(userId: _adminId);
  final container = (await tester.runAsync(
    () => mockContainer(account: account, stored: local ? account.copyWith(apiUrl: null) : account, api: api.answer),
  ))!;
  await container.redux(meProvider).dispatchAsync(RefreshMeAction());

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
    final api = _FakeApi(
      users: [
        fakeUser(id: _adminId, userName: 'alice', role: UserRole.admin),
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
    final container = await _pumpPage(tester, api);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();

    await tester.pumpAndSettle();
    expect(find.text('2 Users'), findsOneWidget);
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
    await tester.pumpAndSettle();
    expect(find.byType(UserPage), findsOneWidget);
    expect(find.text('Sets a new password for bob and signs them out everywhere.'), findsOneWidget);
    expect(find.text('Disabled (signed out everywhere)'), findsOneWidget);
    expect(find.text('Must be changed at the next login'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('user.setPassword'))).enabled, isTrue);
    expect(find.byKey(const ValueKey('user.delete')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(UsersPage), findsOneWidget);

    // Creates a user: the password is checked first, then the API rejects the taken user name.
    await tester.tap(find.byKey(const ValueKey('users.new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('userForm.userName')), 'bob');
    await tester.enterText(find.byKey(const ValueKey('userForm.password')), 'short');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('userForm.save')));
    await tester.pump();
    expect(find.text('Password must be 8 to 128 characters long'), findsWidgets);
    expect(api.registers, isEmpty);
    clearSnackBars();
    await tester.enterText(find.byKey(const ValueKey('userForm.password')), 'secret-password');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('userForm.save')));
    await tester.pump();
    expect(find.text('A user with this user name already exists'), findsWidgets);
    expect(find.byKey(const ValueKey('userForm.save')), findsOneWidget);
    clearSnackBars();
    await tester.enterText(find.byKey(const ValueKey('userForm.userName')), 'carol');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('userForm.save')));
    await tester.pump();
    expect(find.text('User created.'), findsWidgets);
    expect(
      api.registers.last,
      const RegisterRequest(userName: 'carol', email: null, password: 'secret-password', mustChangePassword: true),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('userForm.save')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('3 Users'), findsOneWidget);
    expect(find.text('carol'), findsOneWidget);
  });

  testWidgets('the users page of the local instance offers no new user', (tester) async {
    final api = _FakeApi(
      users: [fakeUser(id: _adminId, userName: 'admin', role: UserRole.admin)],
    );
    await _pumpPage(tester, api, local: true);

    await tester.pumpAndSettle();
    expect(find.text('1 User'), findsOneWidget);
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
