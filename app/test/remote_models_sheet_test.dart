import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/widget/admin/remote_models_sheet.dart';
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
const _existingId = '0199a8d4-6d5e-7c3a-9b1f-000000000020';

/// The API of an admin whose provider lists [remoteModels] (or fails with [listError]) and rejects adding the models
/// named in [rejected]; the actions that add a model are recorded.
class _FakeApi {
  final List<RemoteModelDto> remoteModels;
  final String? listError;
  final Set<String> rejected;
  final requests = <ApiCreateLlmModelAction>[];
  var _nextId = 100;

  _FakeApi({this.remoteModels = const [], this.listError, this.rejected = const {}});

  /// A fresh model id.
  String _newId() => '0199a8d4-6d5e-7c3a-9b1f-${(_nextId++).toString().padLeft(12, '0')}';

  /// Answers the actions of the API.
  void answer(ApiMocks mock) {
    mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _adminId, userName: 'alice', role: UserRole.admin)));
    mock.on<ApiListRemoteModelsAction>((state, action) {
      expect(action.providerId, UuidValue.fromString(_providerId));
      if (listError case final message?) {
        throw apiError(ErrorCode.remoteUnreachable, status: 502, message: message);
      }
      return (state, remoteModels);
    });
    mock.on<ApiCreateLlmModelAction>((state, action) {
      requests.add(action);
      final request = action.request;
      if (rejected.contains(request.apiName)) {
        throw apiError(ErrorCode.validationError, status: 422, message: 'Unsupported model');
      }
      return (
        state,
        fakeLlmModel(id: _newId(), providerId: action.providerId.uuid, apiName: request.apiName, displayName: request.displayName),
      );
    });
  }
}

/// A page with a button that opens the sheet for [provider] and records how it was closed.
class _Host extends StatefulWidget {
  final LlmProviderDto provider;

  const _Host({required this.provider});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  RemoteModelsOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: const ValueKey('open'),
          onPressed: () async {
            final result = await RemoteModelsSheet.show(context, provider: widget.provider, becomesDefault: true);
            setState(() {
              outcome = result;
            });
          },
          child: Text('outcome: $outcome'),
        ),
      ),
    );
  }
}

/// Opens the sheet of [provider] for the admin of [api], whose user is loaded, and waits until it has fetched the models.
Future<RefenaContainer> _pumpSheet(WidgetTester tester, _FakeApi api, LlmProviderDto provider) async {
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
          home: _Host(provider: provider),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the sheet lists the models of the server, marks the added ones, and adds the selected ones', (tester) async {
    final api = _FakeApi(
      remoteModels: [
        fakeRemoteModel(apiName: 'gpt-a', displayName: 'GPT A'),
        fakeRemoteModel(apiName: 'gpt-b'),
        fakeRemoteModel(apiName: 'existing'),
      ],
    );
    final provider = fakeLlmProvider(
      id: _providerId,
      name: 'OpenAI',
      apiFormat: LlmApiFormat.openAi,
      models: [fakeLlmModel(id: _existingId, providerId: _providerId, apiName: 'existing')],
    );
    await _pumpSheet(tester, api, provider);

    expect(find.text('Models of OpenAI'), findsOneWidget);
    expect(find.text('GPT A'), findsOneWidget);
    expect(find.text('gpt-a'), findsOneWidget);
    expect(find.text('gpt-b'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('remoteModels.existing'))).enabled, isFalse);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('remoteModels.existing'))).value, isTrue);
    expect(find.text('Added'), findsOneWidget);
    final add = find.byKey(const ValueKey('remoteModels.add'));
    expect(tester.widget<FilledButton>(add).enabled, isFalse);

    // The search narrows the list, "select all" takes the matches.
    await tester.enterText(find.byKey(const ValueKey('remoteModels.search')), 'gpt');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('remoteModels.existing')), findsNothing);
    expect(find.text('Select all 2 matches'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remoteModels.selectAll')));
    await tester.pumpAndSettle();
    expect(find.text('Add 2 models'), findsOneWidget);
    expect(find.textContaining('the first model added becomes the default'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remoteModels.gpt-b')));
    await tester.pumpAndSettle();
    expect(find.text('Add 1 model'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remoteModels.gpt-b')));
    await tester.pumpAndSettle();

    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('2 models added.'), findsOneWidget);
    expect(api.requests.map((a) => a.providerId), [UuidValue.fromString(_providerId), UuidValue.fromString(_providerId)]);
    expect(api.requests.map((a) => a.request), [
      const LlmModelRequest(apiName: 'gpt-a', displayName: 'GPT A'),
      const LlmModelRequest(apiName: 'gpt-b'),
    ]);
    expect(find.text('outcome: RemoteModelsOutcome.added'), findsOneWidget);
  });

  testWidgets('the sheet stays open with the error when some models cannot be added', (tester) async {
    final api = _FakeApi(
      remoteModels: [
        fakeRemoteModel(apiName: 'good'),
        fakeRemoteModel(apiName: 'bad'),
      ],
      rejected: {'bad'},
    );
    final provider = fakeLlmProvider(id: _providerId, name: 'OpenAI', apiFormat: LlmApiFormat.openAi);
    await _pumpSheet(tester, api, provider);

    await tester.tap(find.byKey(const ValueKey('remoteModels.selectAll')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remoteModels.add')));
    // Shown in the sheet: a snack bar would be behind its barrier.
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('remoteModels.addError')), findsOneWidget);
    expect(find.text('Added 1 of 2 models. bad: The request is invalid.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Added'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('remoteModels.good'))).enabled, isFalse);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('remoteModels.bad'))).value, isTrue);
    expect(find.text('Add 1 model'), findsOneWidget);

    // Closing reports the one that was added.
    await tester.tap(find.byKey(const ValueKey('remoteModels.cancel')));
    await tester.pumpAndSettle();
    expect(find.text('outcome: RemoteModelsOutcome.added'), findsOneWidget);
  });

  testWidgets('the sheet shows the error of the server and offers to add a model by name', (tester) async {
    final api = _FakeApi(listError: 'Could not send the request: connection refused');
    final provider = fakeLlmProvider(id: _providerId, name: 'Broken', apiFormat: LlmApiFormat.openAi, baseUrl: 'http://127.0.0.1:9');
    await _pumpSheet(tester, api, provider);

    expect(find.text('Could not reach the remote server, or it responded with an error.'), findsOneWidget);
    expect(find.text('You can still add the models by name.'), findsOneWidget);
    expect(find.byKey(const ValueKey('remoteModels.retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('remoteModels.add')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('remoteModels.addByName')));
    await tester.pumpAndSettle();
    expect(find.text('outcome: RemoteModelsOutcome.addByName'), findsOneWidget);
  });
}
