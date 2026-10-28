import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/preferences_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _providerA = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0a01';
const _providerB = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0b01';
const _modelFast = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0a02';
const _modelSmart = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0b02';

/// The API of a user and the models it lists; the actions that change the user are recorded.
class _FakeApi {
  List<ModelDto> models;
  UuidValue? defaultModelId;
  String? locale;
  bool autoCommit = false;
  final requests = <Object>[];

  _FakeApi({required this.models});

  /// Answers the actions of [apiProvider].
  void answer(ApiMocks mock) {
    mock.on<ApiGetMeAction>(
      (state, _) => (
        state,
        fakeUser(id: _userId, defaultModelId: defaultModelId?.toString(), locale: locale, autoCommit: autoCommit),
      ),
    );
    mock.on<ApiListModelsAction>((state, _) => (state, models));
    mock.on<ApiSetMyDefaultModelAction>((state, action) {
      requests.add(action);
      final modelId = action.modelId;
      if (modelId != null && !models.any((m) => m.id == modelId)) {
        throw apiError(ErrorCode.unknownModel, status: 404);
      }
      defaultModelId = modelId;
      return state;
    });
    mock.on<ApiSetLocaleAction>((state, action) {
      requests.add(action);
      locale = action.locale;
      return state;
    });
    mock.on<ApiSetAutoCommitAction>((state, action) {
      requests.add(action);
      autoCommit = action.autoCommit;
      return state;
    });
  }
}

/// Opens the page for the user of [api], whose user is loaded.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeApi api) async {
  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: _userId),
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
          home: const PreferencesPage(),
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

  testWidgets('the preferences page sets the model, the language and auto-commit', (tester) async {
    final api = _FakeApi(
      models: [
        fakeModel(id: _modelFast, displayName: 'Fast', providerId: _providerA, providerName: 'Alpha', isDefault: true),
        fakeModel(id: _modelSmart, displayName: 'Smart', providerId: _providerB, providerName: 'Beta'),
      ],
    );
    final container = await _pumpPage(tester, api);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();

    // Without a model of their own, the default one is shown once the models are loaded.
    await tester.pump();
    expect(find.text('Default (Fast)'), findsOneWidget);
    expect(find.text('Device default (en-US)'), findsOneWidget);
    expect(find.byKey(const ValueKey('preferences.autoCommit')), findsOneWidget);

    // A model deleted in the meantime: the models are loaded again, so the sheet no longer offers it.
    await tester.tap(find.byKey(const ValueKey('preferences.model')));
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);
    api.models = [api.models.first];
    await tester.tap(find.byKey(const ValueKey('preferences.model.$_modelSmart')));
    await tester.pumpAndSettle();
    expect(find.text('Could not save the model: The model is no longer available.'), findsOneWidget);
    expect(
      api.requests.last,
      isA<ApiSetMyDefaultModelAction>().having((a) => a.modelId, 'modelId', UuidValue.fromString(_modelSmart)),
    );
    clearSnackBars();
    await tester.tap(find.byKey(const ValueKey('preferences.model')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preferences.model.$_modelSmart')), findsNothing);

    // Chosen: shown with its provider.
    await tester.tap(find.byKey(const ValueKey('preferences.model.$_modelFast')));
    await tester.pumpAndSettle();
    expect(find.text('Model updated.'), findsOneWidget);
    expect(
      api.requests.last,
      isA<ApiSetMyDefaultModelAction>().having((a) => a.modelId, 'modelId', UuidValue.fromString(_modelFast)),
    );
    expect(find.text('Fast (Alpha)'), findsOneWidget);
    expect(container.read(meProvider)?.defaultModelId.toString(), _modelFast);
    clearSnackBars();

    // The language, then back to the device's.
    await tester.tap(find.byKey(const ValueKey('preferences.locale')));
    await tester.pumpAndSettle();
    // Named in English; below the fold of the sheet.
    final deCh = find.byKey(const ValueKey('preferences.locale.de-CH'));
    await tester.scrollUntilVisible(deCh, 100, scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(deCh);
    await tester.pumpAndSettle();
    expect(find.text('German (Switzerland) – de-CH'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preferences.locale.de-CH')));
    await tester.pumpAndSettle();
    expect(find.text('Language updated.'), findsOneWidget);
    expect(api.requests.last, isA<ApiSetLocaleAction>().having((a) => a.locale, 'locale', 'de-CH'));
    expect(find.text('de-CH'), findsOneWidget);
    clearSnackBars();
    await tester.tap(find.byKey(const ValueKey('preferences.locale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preferences.locale.default')));
    await tester.pumpAndSettle();
    expect(find.text('Language updated.'), findsOneWidget);
    expect(api.requests.last, isA<ApiSetLocaleAction>().having((a) => a.locale, 'locale', isNull));
    expect(find.text('Device default (en-US)'), findsOneWidget);
    clearSnackBars();

    // Auto-commit on and off.
    await tester.tap(find.byKey(const ValueKey('preferences.autoCommit')));
    await tester.pumpAndSettle();
    expect(find.text('Proposed changes are now applied automatically.'), findsOneWidget);
    expect(api.requests.last, isA<ApiSetAutoCommitAction>().having((a) => a.autoCommit, 'autoCommit', isTrue));
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('preferences.autoCommit'))).value, isTrue);
    clearSnackBars();
    await tester.tap(find.byKey(const ValueKey('preferences.autoCommit')));
    await tester.pumpAndSettle();
    expect(find.text('Proposed changes now wait for you to apply them.'), findsOneWidget);
    expect(api.requests.last, isA<ApiSetAutoCommitAction>().having((a) => a.autoCommit, 'autoCommit', isFalse));
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('preferences.autoCommit'))).value, isFalse);
  });

  testWidgets('without models, the preferences page says so instead of offering a choice', (tester) async {
    final api = _FakeApi(models: []);
    await _pumpPage(tester, api);
    await tester.pump();
    expect(find.text('No models configured'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preferences.model')));
    await tester.pumpAndSettle();
    expect(find.text('No models configured. Ask an admin to add one.'), findsWidgets);
    expect(find.byKey(const ValueKey('preferences.model.default')), findsNothing);
    expect(api.requests, isEmpty);
  });
}
