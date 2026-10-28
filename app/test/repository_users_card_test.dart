import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:app/widget/form_sheet.dart';
import 'package:app/widget/repositories/repository_users_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/fake_repository.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _bobId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f21';
const _carolId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f22';
const _daveId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f23';
const _repositoryId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';

/// The API of one repository shared with [users]; the changes are recorded in [requests].
class _FakeApi {
  List<RepositoryUserDto> users;
  final requests = <Object>[];

  _FakeApi({required this.users});

  /// The answers to the actions of the card, only for the repository (`NOT_FOUND` otherwise, like the server).
  void answer(ApiMocks mock) {
    mock.on<ApiListRepositoryUsersAction>((state, action) {
      _checkRepository(action.id);
      return (state, users);
    });
    mock.on<ApiAddRepositoryUserAction>((state, action) {
      requests.add(action);
      _checkRepository(action.id);
      if (action.request.userNameOrEmail != 'dave') {
        throw apiError(ErrorCode.unknownUser, status: 422, message: 'There is no user with this user name or email');
      }
      users = [...users, fakeRepositoryUser(userId: _daveId, userName: 'dave')];
      return state;
    });
    mock.on<ApiUpdateRepositoryUserAction>((state, action) {
      requests.add(action);
      _checkRepository(action.id);
      users = [
        for (final user in users)
          if (user.userId == action.userId)
            RepositoryUserDto(
              userId: user.userId,
              userName: user.userName,
              email: user.email,
              canCommit: action.request.canCommit,
              createdAt: user.createdAt,
            )
          else
            user,
      ];
      return state;
    });
    mock.on<ApiRemoveRepositoryUserAction>((state, action) {
      requests.add(action);
      _checkRepository(action.id);
      users = [
        for (final user in users)
          if (user.userId != action.userId) user,
      ];
      return state;
    });
  }

  void _checkRepository(UuidValue id) {
    if (id != UuidValue.fromString(_repositoryId)) {
      throw apiError(ErrorCode.notFound, status: 404, message: 'Repository not found');
    }
  }
}

/// Shows the card for the repository of [api].
Future<RefenaContainer> _pumpCard(WidgetTester tester, _FakeApi api, {bool allowCommits = true, bool local = false}) async {
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: _userId),
      api: api.answer,
    ),
  ))!;
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
    final api = _FakeApi(
      users: [
        fakeRepositoryUser(userId: _bobId, userName: 'bob', email: 'bob@example.com'),
        fakeRepositoryUser(userId: _carolId, userName: 'carol', canCommit: true),
      ],
    );
    final container = await _pumpCard(tester, api);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();
    String lastShared() => (api.requests.last as ApiAddRepositoryUserAction).request.userNameOrEmail;

    await tester.pumpAndSettle();
    expect(find.text('bob'), findsOneWidget);
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
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(FormSheet), matching: find.text('Missing user name or email')), findsOneWidget);
    expect(api.requests, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('repository.share.user')), 'nobody');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repository.share.confirm')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(FormSheet), matching: find.text('No user with this user name or email')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(lastShared(), 'nobody');
    expect(find.byKey(const ValueKey('repository.share.user')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('repository.share.user')), ' dave ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repository.share.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Repository shared.'), findsOneWidget);
    expect(lastShared(), 'dave');
    expect(find.text('dave'), findsOneWidget);
    clearSnackBars();

    // Let bob commit.
    await tester.tap(find.byKey(const ValueKey('repository.users.canCommit.$_bobId')));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('repository.users.canCommit.$_bobId'))).value, isTrue);
    expect(
      api.requests.last,
      isA<ApiUpdateRepositoryUserAction>()
          .having((a) => a.userId, 'userId', UuidValue.fromString(_bobId))
          .having((a) => a.request, 'request', const UpdateRepositoryUserRequest(canCommit: true)),
    );

    // Stop sharing with bob.
    await tester.tap(find.byKey(const ValueKey('repository.users.remove.$_bobId')));
    await tester.pumpAndSettle();
    expect(find.text('bob will lose access to this repository, and it is removed from their chats.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('repository.users.remove.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Stopped sharing.'), findsOneWidget);
    expect(api.requests.last, isA<ApiRemoveRepositoryUserAction>().having((a) => a.userId, 'userId', UuidValue.fromString(_bobId)));
    expect(find.text('bob'), findsNothing);
    expect(find.text('carol'), findsOneWidget);
    expect(find.text('dave'), findsOneWidget);
  });

  testWidgets('without write access, the switch is off and disabled, and a local repository has its own text', (tester) async {
    final api = _FakeApi(
      users: [fakeRepositoryUser(userId: _bobId, userName: 'bob')],
    );
    await _pumpCard(tester, api, allowCommits: false, local: true);
    await tester.pumpAndSettle();
    expect(find.text('bob'), findsOneWidget);
    expect(find.textContaining('cannot change or delete it.'), findsOneWidget);
    expect(find.text('Enable write access for the repository first'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('repository.users.canCommit.$_bobId'))).onChanged, isNull);
  });

  testWidgets('a repository shared with nobody says so', (tester) async {
    await _pumpCard(tester, _FakeApi(users: []));
    await tester.pumpAndSettle();
    expect(find.text('Not shared with anyone'), findsOneWidget);
  });
}
