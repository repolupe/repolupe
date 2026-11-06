import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/mcp_servers_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/mcp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/fake_mcp.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _bobId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f13';
const _searchId = '0199a8d4-6d5e-7c3a-9b1f-000000000041';
const _issuesId = '0199a8d4-6d5e-7c3a-9b1f-000000000042';

/// The API of a user and their MCP servers, which the updates change; the updates are recorded. With [failing], they
/// fail.
class _FakeApi {
  List<McpServerDto> servers;
  final bool canManage;
  final bool failing;
  final updates = <Object>[];

  _FakeApi({required this.servers, this.canManage = true, this.failing = false});

  void answer(ApiMocks mock) {
    mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _userId, canManageMcpServers: canManage)));
    mock.on<ApiListMcpServersAction>((state, _) => (state, servers));
    mock.on<ApiUpdateMcpServerAction>((state, action) {
      updates.add(action);
      if (failing) {
        throw apiError(ErrorCode.forbidden, status: 403);
      }
      final server = servers.firstWhere((s) => s.id == action.id);
      final updated = fakeMcpServer(
        id: server.id.toString(),
        ownerId: _userId,
        name: server.name,
        enabled: action.request.enabled,
        tools: [for (final tool in server.tools) tool.name],
        disabledTools: action.request.disabledTools,
      );
      servers = [for (final s in servers) s.id == action.id ? updated : s];
      return (state, updated);
    });
    mock.on<ApiUpdateMcpServerUserAction>((state, action) {
      updates.add(action);
      if (failing) {
        throw apiError(ErrorCode.validationError);
      }
      servers = [
        for (final s in servers)
          s.id == action.id
              ? fakeMcpServer(
                  id: s.id.toString(),
                  ownerId: _bobId,
                  name: s.name,
                  shared: action.enabled,
                  tools: [for (final tool in s.tools) tool.name],
                )
              : s,
      ];
      return state;
    });
  }
}

Future<void> _pumpPage(WidgetTester tester, _FakeApi api) async {
  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: _userId),
      api: api.answer,
    ),
  ))!;
  await container.redux(meProvider).dispatchAsync(RefreshMeAction());

  // Tall enough that the list builds all of the servers with their tools.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          navigatorKey: container.read(navigationProvider).key,
          scaffoldMessengerKey: container.read(snackBarProvider).key,
          home: const McpServersPage(),
        ),
      ),
    ),
  );
  await tester.pump();
}

SwitchListTile _switch(WidgetTester tester, String key) => tester.widget<SwitchListTile>(find.byKey(ValueKey(key)));

/// Shows the snack bar of the last change, then hides it, so the next one is the only one.
Future<void> _expectSnackBar(WidgetTester tester, String text) async {
  await tester.pump();
  expect(find.text(text), findsOneWidget);
  ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).removeCurrentSnackBar();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the owner turns their server and its tools on or off', (tester) async {
    final api = _FakeApi(
      servers: [
        fakeMcpServer(id: _searchId, ownerId: _userId, name: 'search', tools: ['search', 'fetch']),
      ],
    );
    await _pumpPage(tester, api);

    expect(find.text('1 Server'), findsOneWidget);
    expect(find.text('https://mcp.example.com/mcp'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('2 tools'), findsOneWidget);
    expect(_switch(tester, 'mcpServers.$_searchId.enabled').value, isTrue);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.enabled')));
    await _expectSnackBar(tester, 'search disabled.');
    final turnedOff = api.updates.single as ApiUpdateMcpServerAction;
    expect(turnedOff.id, UuidValue.fromString(_searchId));
    expect(turnedOff.request.enabled, isFalse);
    expect(turnedOff.request.disabledTools, isEmpty);
    expect(_switch(tester, 'mcpServers.$_searchId.enabled').value, isFalse);

    // The tools stay as they are while the server is off for the owner, since others may use it.
    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.tools.fetch')));
    await _expectSnackBar(tester, 'Tool fetch disabled.');
    final toolOff = api.updates.last as ApiUpdateMcpServerAction;
    expect(toolOff.request.enabled, isFalse);
    expect(toolOff.request.disabledTools, ['fetch']);
    expect(find.text('1 of 2 tools enabled'), findsOneWidget);
    expect(_switch(tester, 'mcpServers.$_searchId.tools.fetch').value, isFalse);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.tools.fetch')));
    await _expectSnackBar(tester, 'Tool fetch enabled.');
    expect((api.updates.last as ApiUpdateMcpServerAction).request.disabledTools, isEmpty);
    expect(find.text('2 tools'), findsOneWidget);
  });

  testWidgets('a user turns on a server shared with them, but only its owner chooses its tools', (tester) async {
    final api = _FakeApi(
      servers: [
        fakeMcpServer(id: _issuesId, ownerId: _bobId, name: 'issues', shared: false, tools: ['list_issues']),
      ],
    );
    await _pumpPage(tester, api);

    expect(find.text('Shared by bob'), findsOneWidget);
    expect(find.textContaining('bob shared this server with you'), findsOneWidget);
    expect(_switch(tester, 'mcpServers.$_issuesId.enabled').value, isFalse);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_issuesId.enabled')));
    await _expectSnackBar(tester, 'issues enabled.');
    final turnedOn = api.updates.single as ApiUpdateMcpServerUserAction;
    expect(turnedOn.id, UuidValue.fromString(_issuesId));
    expect(turnedOn.userId, UuidValue.fromString(_userId));
    expect(turnedOn.enabled, isTrue);
    expect(_switch(tester, 'mcpServers.$_issuesId.enabled').value, isTrue);
    expect(find.textContaining('bob shared this server with you'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_issuesId.tools')));
    await tester.pumpAndSettle();
    expect(_switch(tester, 'mcpServers.$_issuesId.tools.list_issues').onChanged, isNull);
  });

  testWidgets('a failed change says so and keeps the switch', (tester) async {
    final api = _FakeApi(
      servers: [fakeMcpServer(id: _issuesId, ownerId: _bobId, name: 'issues', shared: false)],
      failing: true,
    );
    await _pumpPage(tester, api);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_issuesId.enabled')));
    await _expectSnackBar(tester, 'Could not change the server: The request is invalid.');
    expect(_switch(tester, 'mcpServers.$_issuesId.enabled').value, isFalse);
    expect(_switch(tester, 'mcpServers.$_issuesId.enabled').onChanged, isNotNull);
  });

  testWidgets('without the permission, users only turn on the servers shared with them', (tester) async {
    final api = _FakeApi(
      canManage: false,
      servers: [
        fakeMcpServer(id: _searchId, ownerId: _userId, name: 'search'),
        fakeMcpServer(id: _issuesId, ownerId: _bobId, name: 'issues', shared: false),
      ],
    );
    await _pumpPage(tester, api);

    expect(_switch(tester, 'mcpServers.$_searchId.enabled').onChanged, isNull);
    expect(_switch(tester, 'mcpServers.$_issuesId.enabled').onChanged, isNotNull);
    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.tools')));
    await tester.pumpAndSettle();
    expect(_switch(tester, 'mcpServers.$_searchId.tools.search').onChanged, isNull);
  });

  testWidgets('the failed connection of a server is shown, and a server without tools says so', (tester) async {
    final api = _FakeApi(
      servers: [
        fakeMcpServer(id: _searchId, ownerId: _userId, name: 'search', status: McpServerStatus.failed, lastError: 'timed out'),
        fakeMcpServer(id: _issuesId, ownerId: _userId, name: 'issues', tools: const []),
      ],
    );
    await _pumpPage(tester, api);

    expect(find.text('Failed'), findsOneWidget);
    expect(find.byTooltip('The last connection failed: timed out'), findsOneWidget);
    expect(find.text('The server offers no tools.'), findsOneWidget);
  });

  testWidgets('without servers, the page tells where to add them', (tester) async {
    await _pumpPage(tester, _FakeApi(servers: const []));
    expect(find.text('No MCP servers yet'), findsOneWidget);
    expect(find.text('Add an MCP server in the web interface, so the model can use its tools in your chats.'), findsOneWidget);
  });
}
