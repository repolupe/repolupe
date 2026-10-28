import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/config_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/instance_name_provider.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/config.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/instance.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/widget/admin/mistral_key_sheet.dart';
import 'package:app/widget/admin/override_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/api.dart';
import 'support/fake_admin.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _adminId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';

/// The API of an admin with the config, whose overrides `ApiSetConfigAction` replaces (rejecting [rejectedValue]
/// with a message); the set actions are recorded.
class _FakeApi {
  List<ConfigEntryDto> entries;
  String? rejectedValue;
  final sets = <ApiSetConfigAction>[];

  _FakeApi({required this.entries});

  String get instanceName {
    final entry = entries.firstWhere((e) => e.key == 'INSTANCE_NAME');
    return (entry.overrideValue ?? entry.env)!;
  }

  /// Answers the actions of the page with this API.
  void answer(ApiMocks mock) {
    mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _adminId, userName: 'alice', role: UserRole.admin)));
    mock.on<ApiGetInstanceAction>((state, _) => (state, InstanceDto(name: instanceName)));
    mock.on<ApiGetConfigAction>((state, _) => (state, entries));
    mock.on<ApiSetConfigAction>((state, action) {
      sets.add(action);
      if (action.overrides.values.contains(rejectedValue)) {
        throw apiError(ErrorCode.unknown, message: 'OCR_SCAN_CONFIDENCE: expected a number between 0 and 1');
      }
      entries = [
        for (final entry in entries)
          ConfigEntryDto(key: entry.key, env: entry.env, overrideValue: action.overrides[entry.key], runtime: entry.runtime),
      ];
      return (state, entries);
    });
  }
}

/// Opens the page for the admin of [api], whose user is loaded. With [local], the active account is the local
/// instance's, while the actions are answered by [api] all the same.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeApi api, {bool local = false}) async {
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
          home: const ConfigPage(),
        ),
      ),
    ),
  );
  // The page loads after its first frame.
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the config page lists the settings, sets and removes an override with the whole map, and keeps the sheet open on an error', (
    tester,
  ) async {
    final api = _FakeApi(
      entries: [
        fakeConfigEntry(key: 'ADMIN_PASSWORD', env: '******'),
        fakeConfigEntry(key: 'INSTANCE_NAME', env: 'Repolupe', runtime: true),
        fakeConfigEntry(key: 'OCR_API_KEY_MISTRAL', env: '******'),
        fakeConfigEntry(key: 'OCR_ENGINE', env: 'paddle', override: 'none', runtime: true),
        fakeConfigEntry(key: 'OCR_SCAN_CONFIDENCE', env: '0.5', runtime: true),
        fakeConfigEntry(key: 'REPOS_DIR'),
      ],
    );
    final container = await _pumpPage(tester, api);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();
    expect(find.text('Overrides are stored in the database, so they survive restarts of the server.'), findsOneWidget);
    expect(find.textContaining('We recommend', findRichText: true), findsOneWidget);
    // The start page shows the instance name, which an override changes.
    expect(await container.future(instanceNameProvider), 'Repolupe');

    // The rows: the env values (the secret masked, an unset one as "Not set"), the override, and the runtime marker.
    expect(find.text('ADMIN_PASSWORD'), findsOneWidget);
    expect(find.text('Env: ******', findRichText: true), findsNWidgets(2));
    expect(find.text('Env: Repolupe', findRichText: true), findsOneWidget);
    expect(find.text('Env: paddle', findRichText: true), findsOneWidget);
    expect(find.text('Override: none', findRichText: true), findsOneWidget);
    expect(find.text('Env: not set', findRichText: true), findsOneWidget);
    expect(find.text('Runtime'), findsNWidgets(3));
    // Only runtime settings open the sheet.
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('config.entry.REPOS_DIR'))).onTap, isNull);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('config.entry.OCR_API_KEY_MISTRAL'))).onTap, isNull);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('config.entry.INSTANCE_NAME'))).onTap, isNotNull);

    // Set an override: the other override is sent along.
    await tester.tap(find.byKey(const ValueKey('config.entry.INSTANCE_NAME')));
    await tester.pumpAndSettle();
    expect(find.byType(OverrideSheet), findsOneWidget);
    expect(find.descendant(of: find.byType(OverrideSheet), matching: find.text('INSTANCE_NAME')), findsOneWidget);
    // The env value is the hint of the empty field.
    expect(
      tester
          .widget<TextField>(find.descendant(of: find.byKey(const ValueKey('config.override.value')), matching: find.byType(TextField)))
          .decoration
          ?.hintText,
      'Repolupe',
    );
    expect(find.byKey(const ValueKey('config.override.remove')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('config.override.value')), 'Acme Docs');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('config.override.save')));
    await tester.pump();
    expect(find.text('Config updated.'), findsOneWidget);
    expect(api.sets.last.overrides, {'OCR_ENGINE': 'none', 'INSTANCE_NAME': 'Acme Docs'});
    await tester.pumpAndSettle();
    expect(find.byType(OverrideSheet), findsNothing);
    // The response is shown, and the instance name is loaded again.
    expect(find.text('Override: Acme Docs', findRichText: true), findsOneWidget);
    expect(container.read(instanceNameProvider).data, 'Acme Docs');
    clearSnackBars();

    // An enumerated key offers its choices; removing the override sends the map without it.
    await tester.tap(find.byKey(const ValueKey('config.entry.OCR_ENGINE')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('config.override.choice')), findsOneWidget);
    expect(find.byKey(const ValueKey('config.override.value')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('config.override.remove')));
    await tester.pump();
    expect(find.text('Config updated.'), findsOneWidget);
    expect(api.sets.last.overrides, {'INSTANCE_NAME': 'Acme Docs'});
    await tester.pumpAndSettle();
    expect(find.text('Override: none', findRichText: true), findsNothing);
    expect(find.text('Override: Acme Docs', findRichText: true), findsOneWidget);
    clearSnackBars();

    // Choose an engine from the dropdown; without an override, the env value is chosen.
    await tester.tap(find.byKey(const ValueKey('config.entry.OCR_ENGINE')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(OverrideSheet), matching: find.text('(paddle)')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('config.override.choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('mistral').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('config.override.save')));
    await tester.pump();
    expect(find.text('Config updated.'), findsOneWidget);
    expect(api.sets.last.overrides, {'INSTANCE_NAME': 'Acme Docs', 'OCR_ENGINE': 'mistral'});
    await tester.pumpAndSettle();
    expect(find.text('Override: mistral', findRichText: true), findsOneWidget);
    clearSnackBars();

    // A rejected value: the API's message is shown and the sheet stays open with nothing changed.
    api.rejectedValue = 'abc';
    await tester.tap(find.byKey(const ValueKey('config.entry.OCR_SCAN_CONFIDENCE')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('config.override.value')), 'abc');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('config.override.save')));
    await tester.pump();
    expect(find.byKey(const ValueKey('config.override.error')), findsOneWidget);
    expect(find.text('OCR_SCAN_CONFIDENCE: expected a number between 0 and 1'), findsOneWidget);
    expect(api.sets.last.overrides, {'INSTANCE_NAME': 'Acme Docs', 'OCR_ENGINE': 'mistral', 'OCR_SCAN_CONFIDENCE': 'abc'});
    await tester.pumpAndSettle();
    expect(find.byType(OverrideSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('config.override.save')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Override: abc', findRichText: true), findsNothing);
  });

  testWidgets('the config page of the local instance leaves out the advice and the settings the user can\'t change, and sets the Mistral key', (
    tester,
  ) async {
    final api = _FakeApi(
      entries: [
        fakeConfigEntry(key: 'ADMIN_PASSWORD', env: '******'),
        fakeConfigEntry(key: 'INSTANCE_NAME', env: 'Repolupe', runtime: true),
        fakeConfigEntry(key: 'OCR_API_KEY_MISTRAL'),
        fakeConfigEntry(key: 'REPOS_DIR'),
      ],
    );
    await _pumpPage(tester, api, local: true);

    expect(find.text('Overrides are stored in the database, so they survive restarts of the server.'), findsNothing);
    expect(find.textContaining('We recommend', findRichText: true), findsNothing);
    expect(
      find.text('Changing the OCR settings converts all documents again, one at a time. Until then, their earlier text is used.'),
      findsOneWidget,
    );
    expect(find.text('Only runtime settings can be overridden; the others need a restart.'), findsNothing);
    // Only the runtime settings and the Mistral key are listed.
    expect(find.byKey(const ValueKey('config.entry.INSTANCE_NAME')), findsOneWidget);
    expect(find.byKey(const ValueKey('config.entry.OCR_API_KEY_MISTRAL')), findsOneWidget);
    expect(find.byKey(const ValueKey('config.entry.ADMIN_PASSWORD')), findsNothing);
    expect(find.byKey(const ValueKey('config.entry.REPOS_DIR')), findsNothing);

    // The Mistral key opens its sheet; without a key, there is nothing to remove, and nothing to save while empty.
    await tester.tap(find.byKey(const ValueKey('config.entry.OCR_API_KEY_MISTRAL')));
    await tester.pumpAndSettle();
    expect(find.byType(MistralKeySheet), findsOneWidget);
    expect(find.byKey(const ValueKey('config.mistralKey.remove')), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('config.mistralKey.save'))).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('config.mistralKey.value')), 'mistral-key');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('config.mistralKey.save'))).onPressed, isNotNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(MistralKeySheet), findsNothing);
  });
}
