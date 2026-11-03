import 'dart:convert';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/tool_call_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/tool_call.dart';
import 'package:app/widget/chat/tool_call_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _chatId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';

/// A completed call of the tool [name] with [input].
ToolCallSummaryDto _toolCall({required String name, required Map<String, dynamic> input}) => ToolCallSummaryDto(
  id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000007'),
  name: name,
  input: jsonEncode(input),
  status: ToolCallStatus.completed,
  createdAt: DateTime.utc(2026, 11, 2, 12),
);

/// Shows the label of [toolCall].
Future<void> _pumpLabel(WidgetTester tester, ToolCallSummaryDto toolCall) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        home: Scaffold(body: ToolCallLabel(toolCall: toolCall)),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  group('parseMcpToolName', () {
    test('splits the server slug and the tool name', () {
      expect(parseMcpToolName('mcp__github__create_issue'), (server: 'github', tool: 'create_issue'));
      expect(parseMcpToolName('mcp__my_server_2__search'), (server: 'my_server_2', tool: 'search'));
      expect(parseMcpToolName('mcp__docs__files__read'), (server: 'docs', tool: 'files__read'));
    });

    test('returns null for built-in tools and incomplete names', () {
      for (final name in ['read_file', 'mcp__github', 'mcp__github__', 'mcp____tool', 'x_mcp__github__search']) {
        expect(parseMcpToolName(name), isNull, reason: name);
        expect(isMcpToolName(name), isFalse, reason: name);
      }
    });
  });

  testWidgets('a tool of an MCP server shows its own name and the server', (tester) async {
    await _pumpLabel(tester, _toolCall(name: 'mcp__github__create_issue', input: {'repository': 'acme/api', 'title': 'Bug'}));

    expect(find.byIcon(Icons.extension_outlined), findsOneWidget);
    expect(find.text('create_issue'), findsOneWidget);
    expect(find.text('github'), findsOneWidget);
    expect(find.textContaining('mcp__'), findsNothing);
    expect(find.textContaining('acme/api'), findsNothing);
  });

  testWidgets('a tool of an MCP server may contain a double underscore itself', (tester) async {
    await _pumpLabel(tester, _toolCall(name: 'mcp__docs__files__read', input: {}));

    expect(find.text('files__read'), findsOneWidget);
    expect(find.text('docs'), findsOneWidget);
  });

  testWidgets('a built-in tool shows its name and the most telling part of its input', (tester) async {
    await _pumpLabel(tester, _toolCall(name: 'read_file', input: {'repository': 'docs', 'path': 'guide/README.md'}));

    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.text('read_file'), findsOneWidget);
    expect(find.text('guide/README.md'), findsOneWidget);
  });

  for (final name in ['mcp__github', 'mcp__github__']) {
    testWidgets('$name, which only looks like a tool of an MCP server, is shown like any other tool', (tester) async {
      await _pumpLabel(tester, _toolCall(name: name, input: {'query': 'bug'}));

      expect(find.byIcon(Icons.build_outlined), findsOneWidget);
      expect(find.byIcon(Icons.extension_outlined), findsNothing);
      expect(find.text(name), findsOneWidget);
      expect(find.text('{"query":"bug"}'), findsOneWidget);
    });
  }

  testWidgets('the page of a tool of an MCP server is titled with its own name and shows the server', (tester) async {
    final toolCall = _toolCall(name: 'mcp__github__create_issue', input: {'repository': 'acme/api', 'title': 'Bug'});
    final container = (await tester.runAsync(
      () => mockContainer(
        account: fakeAccount(userId: _userId),
        api: (mock) {
          mock.on<ApiGetToolCallAction>((state, _) => (state, ToolCallDto(summary: toolCall, output: 'Created #1')));
        },
      ),
    ))!;
    await tester.pumpWidget(
      RefenaScope.withContainer(
        container: container,
        child: TranslationProvider(
          child: MaterialApp(
            home: ToolCallPage(chatId: UuidValue.fromString(_chatId), toolCall: toolCall),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(AppBar), matching: find.text('create_issue')), findsOneWidget);
    expect(find.text('github'), findsOneWidget);
    expect(find.text('Created #1'), findsOneWidget);
    expect(find.textContaining('mcp__'), findsNothing);
  });
}
