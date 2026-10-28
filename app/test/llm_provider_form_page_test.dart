import 'dart:async';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/llm_provider_form_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/api/mirror.dart';
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
const _providerId = '0199a8d4-6d5e-7c3a-9b1f-000000000010';

/// Opens the name picker of the create form and waits for its suggestions, which come from the Rust crate. Unlike the
/// mocked API actions, that call is answered outside the fake async zone, so pumping alone doesn't get the answer.
Future<void> _openNamePicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('providerForm.name')));
  final anthropic = find.byKey(const ValueKey('providerNamePicker.Anthropic'));
  for (var i = 0; i < 100 && anthropic.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(anthropic, findsOneWidget);
  await tester.pumpAndSettle();
}

/// The API of an admin that accepts providers; the actions that create or update one are recorded.
class _FakeApi {
  final requests = <Object>[];

  /// The request of the only recorded action, which created a provider.
  CreateLlmProviderRequest get createRequest => (requests.single as ApiCreateLlmProviderAction).request;

  /// Answers the actions of the API.
  void answer(ApiMocks mock) {
    mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _adminId, userName: 'alice', role: UserRole.admin)));
    mock.on<ApiCreateLlmProviderAction>((state, action) {
      requests.add(action);
      final request = action.request;
      return (
        state,
        fakeLlmProvider(
          id: _providerId,
          name: request.name,
          apiFormat: request.apiFormat,
          baseUrl: request.baseUrl ?? 'https://api.anthropic.com',
          hasKey: request.apiKey != null,
          currency: request.currency,
        ),
      );
    });
    mock.on<ApiUpdateLlmProviderAction>((state, action) {
      requests.add(action);
      final request = action.request;
      return (
        state,
        fakeLlmProvider(
          id: _providerId,
          name: request.name,
          apiFormat: request.apiFormat,
          baseUrl: request.baseUrl ?? 'https://api.anthropic.com',
          keyHint: 'ab12',
          currency: request.currency,
        ),
      );
    });
  }
}

/// Pumps a list page for the admin of [api], whose user is loaded; the tests push the form above it.
Future<RefenaContainer> _pumpApp(WidgetTester tester, _FakeApi api) async {
  tester.view.physicalSize = const Size(600, 1600);
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
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('creating a provider checks the name, sends the fields, and pops with the provider', (tester) async {
    final api = _FakeApi();
    LlmProviderDto? created;
    final container = await _pumpApp(tester, api);
    unawaited(
      container.global.dispatchAsync(NavigateAction.push<LlmProviderDto>(const LlmProviderFormPage.create())).then((p) => created = p),
    );
    await tester.pumpAndSettle();

    // The form starts with the OpenAI format, the default currency and no key field choice.
    expect(find.byKey(const ValueKey('providerForm.key.keep')), findsNothing);
    expect(find.text('API key'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('providerForm.save')));
    await tester.pump();
    expect(find.text('Missing name'), findsOneWidget);
    expect(api.requests, isEmpty);
    container.read(snackBarProvider).key.currentState!.clearSnackBars();

    // A name of its own, which no suggestion matches.
    await _openNamePicker(tester);
    await tester.enterText(find.byKey(const ValueKey('providerNamePicker.search')), ' step6 ');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerNamePicker.Anthropic')), findsNothing);
    expect(find.text('Use “step6”'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('providerNamePicker.custom')));
    await tester.pumpAndSettle();
    expect(find.text('step6'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('providerForm.format')));
    await tester.pumpAndSettle();
    // The menu shows the items again above the field's own.
    await tester.tap(find.descendant(of: find.byType(Scrollable).last, matching: find.text('Anthropic')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('providerForm.currency')), 'eu');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerForm.currency.USD')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('providerForm.currency.EUR')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('providerForm.apiKey')), 'sk-123');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('providerForm.save')));
    await tester.pumpAndSettle();
    expect(find.text('Provider created.'), findsOneWidget);
    expect(api.createRequest, const CreateLlmProviderRequest(name: 'step6', apiFormat: LlmApiFormat.anthropic, apiKey: 'sk-123', currency: 'EUR'));
    expect(find.byKey(const ValueKey('providerForm.save')), findsNothing);
    expect(created?.name, 'step6');
    expect(created?.apiKey, isNotNull);
  });

  testWidgets('choosing a common provider fills in the form', (tester) async {
    final api = _FakeApi();
    final container = await _pumpApp(tester, api);
    unawaited(container.global.dispatchAsync(NavigateAction.push(const LlmProviderFormPage.create())));
    await tester.pumpAndSettle();

    // All of them while the search is empty, then only the matching ones.
    await _openNamePicker(tester);
    await tester.enterText(find.byKey(const ValueKey('providerNamePicker.search')), 'ak');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerNamePicker.Anthropic')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('providerNamePicker.Aki')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerNamePicker.search')), findsNothing);
    expect(find.text('Aki'), findsOneWidget);
    expect(find.text('https://aki.io/anthropic'), findsOneWidget);
    expect(find.text('EUR'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('providerForm.save')));
    await tester.pumpAndSettle();
    expect(find.text('Provider created.'), findsOneWidget);
    expect(
      api.createRequest,
      const CreateLlmProviderRequest(name: 'Aki', apiFormat: LlmApiFormat.anthropic, baseUrl: 'https://aki.io/anthropic', currency: 'EUR'),
    );
  });

  testWidgets('clearing the currency creates a provider without prices', (tester) async {
    final api = _FakeApi();
    final container = await _pumpApp(tester, api);
    unawaited(container.global.dispatchAsync(NavigateAction.push(const LlmProviderFormPage.create())));
    await tester.pumpAndSettle();

    // The keyboard's "done" takes the name as it is.
    await _openNamePicker(tester);
    await tester.enterText(find.byKey(const ValueKey('providerNamePicker.search')), 'local');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('local'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('providerForm.currency.clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerForm.currency.clear')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('providerForm.save')));
    await tester.pumpAndSettle();
    expect(find.text('Provider created.'), findsOneWidget);
    expect(api.createRequest.currency, isNull);
  });

  testWidgets('editing a provider renames it in place instead of picking a name', (tester) async {
    final api = _FakeApi();
    final provider = fakeLlmProvider(id: _providerId, name: 'Anthropic', keyHint: 'ab12');
    final container = await _pumpApp(tester, api);
    unawaited(container.global.dispatchAsync(NavigateAction.push(LlmProviderFormPage.edit(provider: provider))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('providerForm.name')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerNamePicker.search')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('providerForm.name')), 'Claude');
    await tester.pump();
    expect(find.text('Claude'), findsOneWidget);
  });

  testWidgets('editing a provider keeps the key unless a new one is chosen, which must not be empty', (tester) async {
    final api = _FakeApi();
    final provider = fakeLlmProvider(id: _providerId, name: 'Anthropic', keyHint: 'ab12');
    final container = await _pumpApp(tester, api);
    unawaited(container.global.dispatchAsync(NavigateAction.push(LlmProviderFormPage.edit(provider: provider))));
    await tester.pumpAndSettle();

    // The official base URL is left to the hint, the key is kept by default.
    expect(find.text('(currently •••• ab12)'), findsOneWidget);
    expect(find.byKey(const ValueKey('providerForm.apiKey')), findsNothing);
    expect(find.byKey(const ValueKey('providerForm.hostChanged')), findsNothing);

    // A new key must be entered when chosen.
    await tester.tap(find.byKey(const ValueKey('providerForm.key.set')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerForm.apiKey')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('providerForm.save')));
    await tester.pump();
    expect(find.text('Missing API key'), findsOneWidget);
    expect(api.requests, isEmpty);
    container.read(snackBarProvider).key.currentState!.clearSnackBars();

    // Another host cannot keep the key.
    await tester.tap(find.byKey(const ValueKey('providerForm.key.keep')));
    await tester.enterText(find.byKey(const ValueKey('providerForm.baseUrl')), 'https://proxy.example.com/v1');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerForm.hostChanged')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('providerForm.baseUrl')), '');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('providerForm.hostChanged')), findsNothing);

    // Kept: the name changes, the key is not sent.
    await tester.enterText(find.byKey(const ValueKey('providerForm.name')), 'Anthropic 2');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('providerForm.save')));
    await tester.pumpAndSettle();
    expect(find.text('Provider updated.'), findsOneWidget);
    expect(
      api.requests.single,
      isA<ApiUpdateLlmProviderAction>()
          .having((a) => a.id, 'id', UuidValue.fromString(_providerId))
          .having(
            (a) => a.request,
            'request',
            const UpdateLlmProviderRequest(
              name: 'Anthropic 2',
              apiFormat: LlmApiFormat.anthropic,
              apiKey: ApiKeyChange.keep(),
              currency: 'USD',
            ),
          ),
    );
    expect(find.text('the list'), findsOneWidget);
  });
}
