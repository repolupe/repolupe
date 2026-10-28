import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/llm_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/fake_llm.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _adminId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _anthropicId = '0199a8d4-6d5e-7c3a-9b1f-000000000010';
const _localId = '0199a8d4-6d5e-7c3a-9b1f-000000000011';
const _opusId = '0199a8d4-6d5e-7c3a-9b1f-000000000020';
const _haikuId = '0199a8d4-6d5e-7c3a-9b1f-000000000021';

/// [provider] with [models] instead of its own.
LlmProviderDto _withModels(LlmProviderDto provider, List<LlmModelDto> models) => LlmProviderDto(
  id: provider.id,
  name: provider.name,
  apiFormat: provider.apiFormat,
  baseUrl: provider.baseUrl,
  apiKey: provider.apiKey,
  currency: provider.currency,
  models: models,
  createdAt: provider.createdAt,
  updatedAt: provider.updatedAt,
);

/// [model], being the default model if [isDefault].
LlmModelDto _withDefault(LlmModelDto model, {required bool isDefault}) => LlmModelDto(
  id: model.id,
  providerId: model.providerId,
  apiName: model.apiName,
  displayName: model.displayName,
  maxOutputTokens: model.maxOutputTokens,
  inputPrice: model.inputPrice,
  outputPrice: model.outputPrice,
  cacheReadPrice: model.cacheReadPrice,
  cacheWritePrice: model.cacheWritePrice,
  isDefault: isDefault,
  createdAt: model.createdAt,
  updatedAt: model.updatedAt,
);

/// The API of an admin with [providers], which the actions that change something change; those are recorded.
class _FakeApi {
  List<LlmProviderDto> providers;
  final requests = <Object>[];

  _FakeApi({required this.providers});

  /// Answers the actions of the API.
  void answer(ApiMocks mock) {
    mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _adminId, userName: 'alice', role: UserRole.admin)));
    mock.on<ApiListLlmProvidersAction>((state, _) => (state, providers));
    mock.on<ApiSetDefaultModelAction>((state, action) {
      requests.add(action);
      providers = [
        for (final provider in providers)
          _withModels(provider, [
            for (final model in provider.models) _withDefault(model, isDefault: model.id == action.modelId),
          ]),
      ];
      return state;
    });
    mock.on<ApiDeleteLlmModelAction>((state, action) {
      requests.add(action);
      providers = [
        for (final provider in providers)
          _withModels(provider, [
            for (final model in provider.models)
              if (model.id != action.id) model,
          ]),
      ];
      return state;
    });
    mock.on<ApiDeleteLlmProviderAction>((state, action) {
      requests.add(action);
      providers = [
        for (final provider in providers)
          if (provider.id != action.id) provider,
      ];
      return state;
    });
  }
}

/// Opens the page for the admin of [api], whose user is loaded, and waits until it has loaded the providers.
Future<RefenaContainer> _pumpPage(WidgetTester tester, _FakeApi api) async {
  // Tall enough for both providers with their models, so that the lower card is built too.
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
          home: const LlmPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the LLM page shows the providers with their models, changes the default, and deletes a model and a provider', (
    tester,
  ) async {
    final api = _FakeApi(
      providers: [
        fakeLlmProvider(
          id: _anthropicId,
          name: 'Anthropic',
          keyHint: 'ab12',
          models: [
            fakeLlmModel(
              id: _opusId,
              providerId: _anthropicId,
              apiName: 'claude-opus-5-5',
              displayName: 'Claude Opus 5.5',
              inputPrice: '15',
              outputPrice: '75',
              cacheReadPrice: '1.5',
              isDefault: true,
            ),
            fakeLlmModel(id: _haikuId, providerId: _anthropicId, apiName: 'claude-haiku'),
          ],
        ),
        fakeLlmProvider(
          id: _localId,
          name: 'Local',
          apiFormat: LlmApiFormat.openAi,
          baseUrl: 'http://localhost:11434/v1',
          hasKey: false,
          currency: null,
        ),
      ],
    );
    final container = await _pumpPage(tester, api);
    void clearSnackBars() => container.read(snackBarProvider).key.currentState!.clearSnackBars();

    expect(find.text('2 Models'), findsOneWidget);
    expect(find.text('Anthropic'), findsNWidgets(2)); // The provider's name and its API format.
    expect(find.text('•••• ab12'), findsOneWidget);
    expect(find.text('Claude Opus 5.5'), findsOneWidget);
    expect(find.text('claude-opus-5-5'), findsOneWidget);
    expect(find.text(r'$15.00 in / $75.00 out'), findsOneWidget);
    expect(find.text(r'Cache read $1.50, cache write $15.00'), findsOneWidget);
    expect(find.text('claude-haiku'), findsOneWidget);
    expect(find.text('Price per 1M tokens: Not set'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('http://localhost:11434/v1'), findsOneWidget);
    expect(find.text('None (its models have no prices)'), findsOneWidget);
    expect(find.text('No models yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('llm.noDefault')), findsNothing);

    // The star of the default model is filled and does nothing; the other one makes its model the default.
    final opusStar = find.byKey(const ValueKey('llm.model.$_opusId.default'));
    final haikuStar = find.byKey(const ValueKey('llm.model.$_haikuId.default'));
    expect(tester.widget<IconButton>(opusStar).onPressed, isNull);
    expect(((tester.widget<IconButton>(opusStar).icon) as Icon).icon, Icons.star);
    expect(tester.widget<IconButton>(haikuStar).onPressed, isNotNull);
    expect(((tester.widget<IconButton>(haikuStar).icon) as Icon).icon, Icons.star_border);
    await tester.tap(haikuStar);
    await tester.pump();
    expect(find.text('Default model changed.'), findsOneWidget);
    expect(
      api.requests.last,
      isA<ApiSetDefaultModelAction>().having((a) => a.modelId, 'modelId', UuidValue.fromString(_haikuId)),
    );
    // The providers are loaded again without a progress indicator.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    expect(find.descendant(of: haikuStar, matching: find.byIcon(Icons.star)), findsOneWidget);
    expect(tester.widget<IconButton>(haikuStar).onPressed, isNull);
    expect(((tester.widget<IconButton>(opusStar).icon) as Icon).icon, Icons.star_border);
    clearSnackBars();

    // Delete a model after confirming.
    await tester.tap(find.byKey(const ValueKey('llm.model.$_opusId.delete')));
    await tester.pumpAndSettle();
    expect(find.textContaining('The model Claude Opus 5.5 will be deleted.'), findsOneWidget);
    expect(find.textContaining('It is the default model'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('llm.model.delete.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Model deleted.'), findsOneWidget);
    expect(api.requests.last, isA<ApiDeleteLlmModelAction>().having((a) => a.id, 'id', UuidValue.fromString(_opusId)));
    expect(find.text('Claude Opus 5.5'), findsNothing);
    expect(find.text('1 Model'), findsOneWidget);
    clearSnackBars();

    // Delete a provider after typing its name.
    await tester.tap(find.byKey(const ValueKey('llm.provider.$_localId.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete provider'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The provider Local will be deleted, together with its 0 models.'), findsOneWidget);
    final confirm = find.byKey(const ValueKey('llm.provider.delete.confirm'));
    expect(tester.widget<FilledButton>(confirm).enabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('llm.provider.delete.verification')), 'Local');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Provider deleted.'), findsOneWidget);
    expect(api.requests.last, isA<ApiDeleteLlmProviderAction>().having((a) => a.id, 'id', UuidValue.fromString(_localId)));
    expect(find.text('http://localhost:11434/v1'), findsNothing);
    expect(find.byKey(const ValueKey('llm.provider.$_localId')), findsNothing);
    expect(find.byKey(const ValueKey('llm.provider.$_anthropicId')), findsOneWidget);
  });

  testWidgets('the LLM page without providers offers to create one, and warns without a default model', (tester) async {
    final api = _FakeApi(providers: []);
    await _pumpPage(tester, api);
    expect(find.text('No providers yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('llm.empty.newProvider')), findsOneWidget);
    expect(find.byKey(const ValueKey('llm.newProvider')), findsNothing);

    // A provider whose model is not the default.
    api.providers = [
      fakeLlmProvider(
        id: _anthropicId,
        models: [fakeLlmModel(id: _haikuId, providerId: _anthropicId, apiName: 'claude-haiku')],
      ),
    ];
    await tester.pumpWidget(const SizedBox());
    await _pumpPage(tester, api);
    expect(find.byKey(const ValueKey('llm.noDefault')), findsOneWidget);
    expect(find.byKey(const ValueKey('llm.newProvider')), findsOneWidget);
  });
}
