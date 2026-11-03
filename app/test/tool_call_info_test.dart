import 'dart:convert';

import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/chat/tool_call_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';

/// A completed call of the tool [name] with [input], whose repository is [repositoryId].
ToolCallSummaryDto _toolCall({required String name, required Map<String, dynamic> input, String? repositoryId}) =>
    ToolCallSummaryDto(
      id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000007'),
      name: name,
      input: jsonEncode(input),
      repositoryId: repositoryId == null ? null : UuidValue.fromString(repositoryId),
      status: ToolCallStatus.completed,
      createdAt: DateTime.utc(2026, 11, 2, 12),
    );

/// Shows the location of [toolCall] in a chat without repositories.
Future<void> _pumpLocation(WidgetTester tester, ToolCallSummaryDto toolCall, {String? path}) async {
  final container = (await tester.runAsync(() => mockContainer(account: fakeAccount(userId: _userId))))!;
  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          home: Scaffold(body: ToolCallLocation(toolCall: toolCall, path: path)),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('a built-in tool shows the repository the model named if it is not in the chat', (tester) async {
    final toolCall = _toolCall(
      name: 'read_file',
      input: {'repository': 'docs', 'path': 'README.md'},
      repositoryId: '0199a8d4-6d5e-7c3a-9b1f-000000000006',
    );
    await _pumpLocation(tester, toolCall, path: 'README.md');

    expect(find.text('docs › README.md'), findsOneWidget);
  });

  testWidgets('a tool of an MCP server shows no repository for its repository input', (tester) async {
    final toolCall = _toolCall(name: 'mcp__github__create_issue', input: {'repository': 'acme/api', 'title': 'Bug'});
    await _pumpLocation(tester, toolCall);

    expect(find.textContaining('acme/api'), findsNothing);
    expect(find.byType(Text), findsNothing);
  });
}
