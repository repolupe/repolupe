import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/mcp_servers_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/api/error.dart';
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
const _carolId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f14';
const _searchId = '0199a8d4-6d5e-7c3a-9b1f-000000000041';
const _issuesId = '0199a8d4-6d5e-7c3a-9b1f-000000000042';
const _newId = '0199a8d4-6d5e-7c3a-9b1f-000000000043';

/// The API of a user and their MCP servers, which the actions change; the changing actions are recorded. With
/// [failing], the updates fail.
class _FakeApi {
  List<McpServerDto> servers;
  final bool canManage;
  final bool failing;

  /// The users the servers are shared with.
  final users = <UuidValue, List<McpServerUserDto>>{};

  /// The status of the servers it adds.
  McpServerStatus createdStatus = McpServerStatus.ready;

  /// What adding a server fails with, if it does.
  ClientError? createError;
  final actions = <Object>[];

  _FakeApi({required this.servers, this.canManage = true, this.failing = false});

  T last<T>() => actions.whereType<T>().last;

  void answer(ApiMocks mock) {
    mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _userId, canManageMcpServers: canManage)));
    mock.on<ApiListMcpServersAction>((state, _) => (state, servers));
    mock.on<ApiCreateMcpServerAction>((state, action) {
      actions.add(action);
      if (createError case final error?) {
        throw error;
      }
      final request = action.request;
      final server = fakeMcpServer(
        id: _newId,
        ownerId: _userId,
        name: request.name,
        url: request.url,
        auth: request.token == null ? McpServerAuth.none : McpServerAuth.token,
        tokenHint: request.token?.substring(request.token!.length - 4),
        status: createdStatus,
        tools: createdStatus == McpServerStatus.ready ? ['search_code'] : const [],
      );
      servers = [...servers, server];
      return (state, server);
    });
    mock.on<ApiUpdateMcpServerAction>((state, action) {
      actions.add(action);
      if (failing) {
        throw apiError(ErrorCode.forbidden, status: 403);
      }
      final server = servers.firstWhere((s) => s.id == action.id);
      final updated = fakeMcpServer(
        id: server.id.toString(),
        ownerId: _userId,
        name: action.request.name,
        enabled: action.request.enabled,
        tools: [for (final tool in server.tools) tool.name],
        disabledTools: action.request.disabledTools,
      );
      servers = [for (final s in servers) s.id == action.id ? updated : s];
      return (state, updated);
    });
    mock.on<ApiUpdateMcpServerUserAction>((state, action) {
      actions.add(action);
      if (failing) {
        throw apiError(ErrorCode.validationError, message: 'You can use at most 20 MCP servers');
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
    mock.on<ApiDeleteMcpServerAction>((state, action) {
      actions.add(action);
      servers = [
        for (final s in servers)
          if (s.id != action.id) s,
      ];
      return state;
    });
    mock.on<ApiRefreshMcpServerAction>((state, action) {
      actions.add(action);
      final server = servers.firstWhere((s) => s.id == action.id);
      final refreshed = fakeMcpServer(id: server.id.toString(), ownerId: _userId, name: server.name, tools: ['search', 'fetch', 'crawl']);
      servers = [for (final s in servers) s.id == action.id ? refreshed : s];
      return (state, refreshed);
    });
    mock.on<ApiListMcpServerUsersAction>((state, action) => (state, users[action.id] ?? const []));
    mock.on<ApiAddMcpServerUserAction>((state, action) {
      actions.add(action);
      if (action.request.userNameOrEmail != 'carol') {
        throw apiError(ErrorCode.unknownUser, status: 422);
      }
      users[action.id] = [...?users[action.id], fakeMcpServerUser(id: _carolId, userName: 'carol')];
      return state;
    });
    mock.on<ApiRemoveMcpServerUserAction>((state, action) {
      actions.add(action);
      users[action.id] = [
        for (final u in users[action.id] ?? const <McpServerUserDto>[])
          if (u.userId != action.userId) u,
      ];
      if (action.userId == UuidValue.fromString(_userId)) {
        servers = [
          for (final s in servers)
            if (s.id != action.id) s,
        ];
      }
      return state;
    });
  }
}

/// Pumps the page for the user of [api], on a server or, with [local], on the local instance.
Future<void> _pumpPage(WidgetTester tester, _FakeApi api, {bool local = false}) async {
  final account = fakeAccount(userId: _userId);
  final container = (await tester.runAsync(
    () => mockContainer(
      account: account,
      stored: local ? account.copyWith(apiUrl: null) : account,
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
  // Until the button to add a server has appeared.
  await tester.pumpAndSettle();
}

SwitchListTile _switch(WidgetTester tester, String key) => tester.widget<SwitchListTile>(find.byKey(ValueKey(key)));

/// Shows the snack bar of the last change, then hides it, so the next one is the only one.
Future<void> _expectSnackBar(WidgetTester tester, String text) async {
  await tester.pump();
  expect(find.text(text), findsOneWidget);
  ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).removeCurrentSnackBar();
  await tester.pump();
}

/// Opens the name picker of the create form and waits for its suggestions, which come from the Rust crate. Unlike the
/// mocked API actions, that call is answered outside the fake async zone, so pumping alone doesn't get the answer.
Future<void> _openNamePicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('mcpServerForm.name')));
  final exa = find.byKey(const ValueKey('mcpServerNamePicker.Exa'));
  for (var i = 0; i < 100 && exa.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(exa, findsOneWidget);
  await tester.pumpAndSettle();
}

/// Opens the menu of the server [id] and chooses [action] in it.
Future<void> _choose(WidgetTester tester, String id, String action) async {
  await tester.tap(find.byKey(ValueKey('mcpServers.$id.menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('mcpServers.$id.$action')));
  await tester.pumpAndSettle();
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
    expect(find.textContaining('No authentication'), findsOneWidget);
    expect(find.text('2 tools'), findsOneWidget);
    expect(_switch(tester, 'mcpServers.$_searchId.enabled').value, isTrue);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.enabled')));
    await _expectSnackBar(tester, 'search disabled.');
    final turnedOff = api.actions.single as ApiUpdateMcpServerAction;
    expect(turnedOff.id, UuidValue.fromString(_searchId));
    expect(turnedOff.request.enabled, isFalse);
    expect(turnedOff.request.disabledTools, isEmpty);
    expect(_switch(tester, 'mcpServers.$_searchId.enabled').value, isFalse);
    expect(find.text('Not used in chats'), findsOneWidget);

    // The tools stay as they are while the server is off for the owner, since others may use it.
    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.tools.fetch')));
    await _expectSnackBar(tester, 'Tool fetch disabled.');
    final toolOff = api.last<ApiUpdateMcpServerAction>();
    expect(toolOff.request.enabled, isFalse);
    expect(toolOff.request.disabledTools, ['fetch']);
    expect(find.text('1 of 2 tools enabled'), findsOneWidget);
    expect(_switch(tester, 'mcpServers.$_searchId.tools.fetch').value, isFalse);
    expect(_switch(tester, 'mcpServers.$_searchId.tools.all').value, isFalse);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.tools.fetch')));
    await _expectSnackBar(tester, 'Tool fetch enabled.');
    expect(api.last<ApiUpdateMcpServerAction>().request.disabledTools, isEmpty);
    expect(find.text('2 tools'), findsOneWidget);
  });

  testWidgets('all tools are turned on or off at once, keeping the names the server no longer lists', (tester) async {
    final api = _FakeApi(
      servers: [
        fakeMcpServer(id: _searchId, ownerId: _userId, tools: ['search', 'fetch'], disabledTools: ['fetch', 'gone']),
      ],
    );
    await _pumpPage(tester, api);
    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.tools')));
    await tester.pumpAndSettle();

    // Some tools off counts as off.
    expect(_switch(tester, 'mcpServers.$_searchId.tools.all').value, isFalse);
    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.tools.all')));
    await _expectSnackBar(tester, 'All tools of search enabled.');
    expect(api.last<ApiUpdateMcpServerAction>().request.disabledTools, ['gone']);
    expect(_switch(tester, 'mcpServers.$_searchId.tools.all').value, isTrue);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.tools.all')));
    await _expectSnackBar(tester, 'All tools of search disabled.');
    expect(api.last<ApiUpdateMcpServerAction>().request.disabledTools, ['gone', 'search', 'fetch']);
    expect(find.text('0 of 2 tools enabled'), findsOneWidget);
    expect(find.text('Not used in chats'), findsOneWidget);
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
    // Only the owner shares it.
    expect(find.byKey(const ValueKey('mcpServers.$_issuesId.sharing')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_issuesId.enabled')));
    await _expectSnackBar(tester, 'issues enabled.');
    final turnedOn = api.actions.single as ApiUpdateMcpServerUserAction;
    expect(turnedOn.id, UuidValue.fromString(_issuesId));
    expect(turnedOn.userId, UuidValue.fromString(_userId));
    expect(turnedOn.enabled, isTrue);
    expect(_switch(tester, 'mcpServers.$_issuesId.enabled').value, isTrue);
    expect(find.textContaining('bob shared this server with you'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_issuesId.tools')));
    await tester.pumpAndSettle();
    expect(_switch(tester, 'mcpServers.$_issuesId.tools.list_issues').onChanged, isNull);
    expect(_switch(tester, 'mcpServers.$_issuesId.tools.all').onChanged, isNull);
  });

  testWidgets('a user leaves a server shared with them', (tester) async {
    final api = _FakeApi(
      servers: [fakeMcpServer(id: _issuesId, ownerId: _bobId, name: 'issues', shared: true)],
    );
    await _pumpPage(tester, api);

    await _choose(tester, _issuesId, 'leave');
    expect(find.textContaining('You can no longer use the tools of issues'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcpServers.leave.confirm')));
    await tester.pumpAndSettle();

    final left = api.actions.single as ApiRemoveMcpServerUserAction;
    expect(left.id, UuidValue.fromString(_issuesId));
    expect(left.userId, UuidValue.fromString(_userId));
    expect(find.text('You left issues.'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcpServers.$_issuesId')), findsNothing);
  });

  testWidgets('a failed change says so with the reason and keeps the switch', (tester) async {
    final api = _FakeApi(
      servers: [fakeMcpServer(id: _issuesId, ownerId: _bobId, name: 'issues', shared: false)],
      failing: true,
    );
    await _pumpPage(tester, api);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_issuesId.enabled')));
    await _expectSnackBar(tester, 'Could not change the server: You can use at most 20 MCP servers');
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

    expect(find.byKey(const ValueKey('mcpServers.new')), findsNothing);
    expect(find.byKey(const ValueKey('mcpServers.$_searchId.menu')), findsNothing);
    expect(find.byKey(const ValueKey('mcpServers.$_searchId.sharing')), findsNothing);
    expect(find.byKey(const ValueKey('mcpServers.$_issuesId.menu')), findsOneWidget);
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
    expect(find.text('The last connection failed: timed out'), findsOneWidget);
    expect(find.text('The server offers no tools.'), findsOneWidget);
  });

  testWidgets('users a server is shared with only learn that its connection failed', (tester) async {
    final api = _FakeApi(
      servers: [fakeMcpServer(id: _issuesId, ownerId: _bobId, shared: true, status: McpServerStatus.failed)],
    );
    await _pumpPage(tester, api);
    expect(find.text('The last connection failed. Only the owner sees why.'), findsOneWidget);
  });

  testWidgets('a server that asks to sign in says that the app cannot sign in to it yet', (tester) async {
    final api = _FakeApi(
      servers: [
        fakeMcpServer(id: _searchId, ownerId: _userId, auth: McpServerAuth.none, status: McpServerStatus.authorizationRequired, tools: const []),
        fakeMcpServer(id: _issuesId, ownerId: _bobId, shared: true, status: McpServerStatus.authorizationRequired, tools: const []),
      ],
    );
    await _pumpPage(tester, api);

    expect(find.text('Sign-in required'), findsNWidgets(2));
    final ownWarning = find.byKey(const ValueKey('mcpServers.$_searchId.signIn'));
    expect(find.descendant(of: ownWarning, matching: find.textContaining('which the app does not support yet. Sign in in the web')), findsOneWidget);
    final sharedWarning = find.byKey(const ValueKey('mcpServers.$_issuesId.signIn'));
    expect(find.descendant(of: sharedWarning, matching: find.textContaining('asks its owner to sign in again')), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('the local instance shares no servers and has no web interface to sign in', (tester) async {
    final api = _FakeApi(
      servers: [fakeMcpServer(id: _searchId, ownerId: _userId, status: McpServerStatus.authorizationRequired, tools: const [])],
    );
    await _pumpPage(tester, api, local: true);

    final warning = find.byKey(const ValueKey('mcpServers.$_searchId.signIn'));
    expect(find.descendant(of: warning, matching: find.textContaining('which the app does not support yet.')), findsOneWidget);
    expect(find.descendant(of: warning, matching: find.textContaining('web interface')), findsNothing);
    expect(find.byKey(const ValueKey('mcpServers.$_searchId.sharing')), findsNothing);
    expect(find.byKey(const ValueKey('mcpServers.$_searchId.menu')), findsOneWidget);
  });

  testWidgets('the owner adds a common server with a token', (tester) async {
    final api = _FakeApi(
      servers: [fakeMcpServer(id: _searchId, ownerId: _userId)],
    );
    await _pumpPage(tester, api);

    await tester.tap(find.byKey(const ValueKey('mcpServers.new')));
    await tester.pumpAndSettle();
    expect(find.text('New Server'), findsOneWidget);

    await _openNamePicker(tester);
    await tester.enterText(find.byKey(const ValueKey('mcpServerNamePicker.search')), 'git');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mcpServerNamePicker.Exa')), findsNothing);
    expect(find.text('Developer tools'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcpServerNamePicker.GitHub')));
    await tester.pumpAndSettle();

    expect(find.text('https://api.githubcopilot.com/mcp'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('mcpServerForm.token')), ' ghp_secret1234 ');
    await tester.tap(find.byKey(const ValueKey('mcpServerForm.save')));
    await tester.pumpAndSettle();

    final request = (api.actions.single as ApiCreateMcpServerAction).request;
    expect(request.name, 'GitHub');
    expect(request.url, 'https://api.githubcopilot.com/mcp');
    expect(request.token, 'ghp_secret1234');
    expect(find.text('Server added.'), findsOneWidget);
    expect(find.text('2 Servers'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcpServers.$_newId')), findsOneWidget);
    expect(find.textContaining('Token •••• 1234'), findsOneWidget);
  });

  testWidgets('a server of the user\'s own name is added by its URL, and one that asks to sign in says so', (tester) async {
    final api = _FakeApi(servers: const [])..createdStatus = McpServerStatus.authorizationRequired;
    await _pumpPage(tester, api);

    expect(find.text('Add an MCP server by its URL, so the model can use its tools in your chats.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcpServers.new')));
    await tester.pumpAndSettle();
    await _openNamePicker(tester);
    await tester.enterText(find.byKey(const ValueKey('mcpServerNamePicker.search')), ' Notes ');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mcpServerNamePicker.custom')));
    await tester.pumpAndSettle();

    // Without a URL, nothing is sent.
    await tester.tap(find.byKey(const ValueKey('mcpServerForm.save')));
    await tester.pump();
    expect(find.text('Missing URL'), findsOneWidget);
    expect(api.actions, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('mcpServerForm.url')), 'https://notes.example.com/mcp');
    await tester.tap(find.byKey(const ValueKey('mcpServerForm.save')));
    await tester.pumpAndSettle();

    final request = (api.actions.single as ApiCreateMcpServerAction).request;
    expect(request.name, 'Notes');
    expect(request.token, isNull);
    expect(find.text('Server added. It asks you to sign in, which the app does not support yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcpServers.$_newId.signIn')), findsOneWidget);
  });

  testWidgets('a server that cannot be reached is not added, and the form tells why', (tester) async {
    final api = _FakeApi(
      servers: [fakeMcpServer(id: _searchId, ownerId: _userId)],
    )..createError = apiError(ErrorCode.remoteUnreachable, status: 502, message: 'Connection refused');
    await _pumpPage(tester, api);

    await tester.tap(find.byKey(const ValueKey('mcpServers.new')));
    await tester.pumpAndSettle();
    await _openNamePicker(tester);
    await tester.tap(find.byKey(const ValueKey('mcpServerNamePicker.Exa')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mcpServerForm.save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not add the server: Connection refused. Check the URL'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcpServerForm.save')), findsOneWidget);
  });

  testWidgets('the owner renames a server, whose URL and token stay', (tester) async {
    final api = _FakeApi(
      servers: [
        fakeMcpServer(id: _searchId, ownerId: _userId, name: 'search', enabled: false, tools: ['search', 'fetch'], disabledTools: ['fetch']),
      ],
    );
    await _pumpPage(tester, api);

    await _choose(tester, _searchId, 'edit');
    expect(find.text('Edit Server'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('mcpServerForm.url'))).enabled, isFalse);
    expect(find.byKey(const ValueKey('mcpServerForm.token')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('mcpServerForm.name')), 'web search');
    await tester.tap(find.byKey(const ValueKey('mcpServerForm.save')));
    await tester.pumpAndSettle();

    final update = api.actions.single as ApiUpdateMcpServerAction;
    expect(update.request.name, 'web search');
    expect(update.request.enabled, isFalse);
    expect(update.request.disabledTools, ['fetch']);
    expect(find.text('Server updated.'), findsOneWidget);
    expect(find.text('web search'), findsOneWidget);
  });

  testWidgets('the owner refreshes and deletes a server', (tester) async {
    final api = _FakeApi(
      servers: [fakeMcpServer(id: _searchId, ownerId: _userId, status: McpServerStatus.failed, lastError: 'timed out')],
    );
    await _pumpPage(tester, api);

    await _choose(tester, _searchId, 'refresh');
    expect(find.text('Connected, the server offers 3 tools.'), findsOneWidget);
    expect((api.actions.single as ApiRefreshMcpServerAction).id, UuidValue.fromString(_searchId));
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('3 tools'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await _choose(tester, _searchId, 'delete');
    expect(find.textContaining('The MCP server search will be deleted.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcpServers.delete.confirm')));
    await tester.pumpAndSettle();

    expect((api.last<ApiDeleteMcpServerAction>()).id, UuidValue.fromString(_searchId));
    expect(find.text('Server deleted.'), findsOneWidget);
    expect(find.text('No MCP servers yet'), findsOneWidget);
  });

  testWidgets('the owner shares a server and stops sharing it', (tester) async {
    final api = _FakeApi(
      servers: [fakeMcpServer(id: _searchId, ownerId: _userId)],
    );
    api.users[UuidValue.fromString(_searchId)] = [fakeMcpServerUser(id: _bobId, userName: 'bob', email: 'bob@example.com')];
    await _pumpPage(tester, api);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.sharing')));
    await tester.pumpAndSettle();
    expect(find.text('bob'), findsOneWidget);
    expect(find.textContaining('bob@example.com'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.share')));
    await tester.pumpAndSettle();
    expect(find.text('Share MCP Server'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('mcpServers.share.user')), 'nobody');
    await tester.tap(find.byKey(const ValueKey('mcpServers.share.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('No user with this user name or email'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('mcpServers.share.user')), ' carol ');
    await tester.tap(find.byKey(const ValueKey('mcpServers.share.confirm')));
    await tester.pumpAndSettle();
    expect(api.last<ApiAddMcpServerUserAction>().request.userNameOrEmail, 'carol');
    expect(find.text('Server shared.'), findsOneWidget);
    expect(find.text('carol'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mcpServers.$_searchId.users.remove.$_bobId')));
    await tester.pumpAndSettle();
    expect(find.text('bob can no longer use the tools of this server in their chats.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcpServers.users.remove.confirm')));
    await tester.pumpAndSettle();

    final removed = api.last<ApiRemoveMcpServerUserAction>();
    expect(removed.id, UuidValue.fromString(_searchId));
    expect(removed.userId, UuidValue.fromString(_bobId));
    expect(find.text('Stopped sharing.'), findsOneWidget);
    expect(find.text('bob'), findsNothing);
  });

  testWidgets('without servers, the page offers to add one', (tester) async {
    await _pumpPage(tester, _FakeApi(servers: const []));
    expect(find.text('No MCP servers yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcpServers.new')), findsOneWidget);
  });

  testWidgets('without servers and the permission, the page tells how users get one', (tester) async {
    await _pumpPage(tester, _FakeApi(servers: const [], canManage: false));
    expect(find.textContaining('No MCP servers have been shared with you.'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcpServers.new')), findsNothing);
  });
}
