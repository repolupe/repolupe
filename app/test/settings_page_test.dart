import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/api.dart';
import 'support/fake_repository.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _adminId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _providerId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f13';
const _modelId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f14';

/// The subtitle of the tile with [key], `null` if it has none.
String? _subtitle(WidgetTester tester, String key) {
  final subtitle = tester.widget<ListTile>(find.byKey(ValueKey(key))).subtitle;
  return subtitle == null ? null : (subtitle as Text).data;
}

/// Opens the settings for an admin with two repositories and one model (the default). With [local], the active
/// account is the local instance's, while the requests are answered all the same.
Future<void> _pumpPage(WidgetTester tester, {required bool local, String? fullName, String? locale}) async {
  final account = fakeAccount(userId: _adminId, userName: 'admin');
  final container = (await tester.runAsync(
    () => mockContainer(
      account: account,
      stored: local ? account.copyWith(apiUrl: null) : account,
      api: (mock) {
        mock.on<ApiGetMeAction>(
          (state, _) => (
            state,
            fakeUser(id: _adminId, userName: 'admin', role: UserRole.admin, fullName: fullName, locale: locale),
          ),
        );
        mock.on<ApiListRepositoriesAction>(
          (state, _) => (
            state,
            [
              fakeRepository(id: '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f15', ownerId: _adminId),
              fakeRepository(id: '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f16', ownerId: _adminId, name: 'handbook'),
            ],
          ),
        );
        mock.on<ApiListModelsAction>(
          (state, _) => (
            state,
            [
              fakeModel(
                id: _modelId,
                displayName: 'Fast',
                providerId: _providerId,
                providerName: 'Acme',
                isDefault: true,
              ),
            ],
          ),
        );
      },
    ),
  ))!;
  await container.redux(meProvider).dispatchAsync(RefreshMeAction());

  // Tall enough that the list builds all of its sections.
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          navigatorKey: container.read(navigationProvider).key,
          home: const SettingsPage(),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the settings of an admin offer the users', (tester) async {
    await _pumpPage(tester, local: false);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.accounts')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.admin.users')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.admin.llm')), findsOneWidget);
  });

  testWidgets('the settings of the local instance offer no users, its admin is its only user', (tester) async {
    await _pumpPage(tester, local: true);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.admin.users')), findsNothing);
    expect(find.byKey(const ValueKey('settings.admin.llm')), findsOneWidget);
  });

  testWidgets('the user sections show their state', (tester) async {
    await _pumpPage(tester, local: false, fullName: 'Ada Admin', locale: 'de-CH');
    await tester.pump();
    expect(find.text('2 repositories'), findsOneWidget);
    expect(_subtitle(tester, 'settings.account'), 'admin • alice@example.com');
    expect(_subtitle(tester, 'settings.profile'), 'Ada Admin');
    expect(_subtitle(tester, 'settings.preferences'), 'Fast • de-CH');
  });

  testWidgets('an empty profile says so', (tester) async {
    await _pumpPage(tester, local: false);
    expect(_subtitle(tester, 'settings.profile'), 'Not filled in yet');
  });

  testWidgets('the admin sections have no subtitle', (tester) async {
    await _pumpPage(tester, local: false);
    for (final key in ['users', 'llm', 'extraction', 'config', 'server']) {
      expect(_subtitle(tester, 'settings.admin.$key'), isNull, reason: key);
    }
  });
}
