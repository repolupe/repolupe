import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/chat/duration_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/rust.dart';

final _createdAt = DateTime.utc(2026, 11, 6, 12);

ToolCallSummaryDto _toolCall(int n, String name, {required int startMs, required int? durationMs}) => ToolCallSummaryDto(
  id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-00000000010$n'),
  name: name,
  input: '{}',
  status: durationMs == null ? ToolCallStatus.running : ToolCallStatus.completed,
  durationMs: durationMs,
  createdAt: _createdAt.add(Duration(milliseconds: startMs)),
);

MessageDto _answer({
  MessageStatus status = MessageStatus.completed,
  List<ToolCallSummaryDto> toolCalls = const [],
  Duration? took = const Duration(seconds: 125, milliseconds: 990),
  UsageDto? usage,
  int? responseMs,
}) => MessageDto(
  id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000001'),
  role: MessageRole.assistant,
  content: 'Done',
  status: status,
  modelName: 'Claude',
  toolCalls: toolCalls,
  createdAt: _createdAt,
  finishedAt: took == null ? null : _createdAt.add(took),
  usage: usage,
  responseMs: responseMs,
);

/// Opens the sheet from a button, like the duration under an answer.
Future<void> _openSheet(WidgetTester tester, MessageDto message) async {
  final container = (await tester.runAsync(() => mockContainer(account: fakeAccount(userId: 'user'))))!;
  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => DurationSheet.show(context, message: message),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The value in the row of [label].
String _value(WidgetTester tester, String label) {
  final row = find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
  return tester.widget<Text>(find.descendant(of: row, matching: find.byType(Text)).last).data!;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('shows how long the language model took, its speed and the total', (tester) async {
    await _openSheet(
      tester,
      _answer(
        usage: const UsageDto(inputTokens: 1200, outputTokens: 3000, cacheReadTokens: 0, cacheWriteTokens: 0),
        responseMs: 24000,
      ),
    );

    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(_value(tester, 'Language model'), '24.0s');
    expect(_value(tester, 'Output speed'), '125 tok/s');
    // Rounded down, like the duration below the answer
    expect(_value(tester, 'Total'), '2m 05s');
    expect(find.text('Tool calls'), findsNothing);
    expect(find.textContaining('was not measured'), findsNothing);
  });

  testWidgets('groups the finished tool calls by tool, the longest first', (tester) async {
    await _openSheet(
      tester,
      _answer(
        responseMs: 5000,
        toolCalls: [
          // The first two run at the same time, the third after them
          _toolCall(1, 'grep', startMs: 1000, durationMs: 400),
          _toolCall(2, 'mcp__github__search_code', startMs: 1000, durationMs: 1500),
          _toolCall(3, 'grep', startMs: 4000, durationMs: 50),
          _toolCall(4, 'read_file', startMs: 6000, durationMs: null),
        ],
      ),
    );

    expect(_value(tester, 'search_code'), '1.5s');
    expect(find.text('github'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    expect(_value(tester, 'grep'), '0.4s');
    expect(find.text('2×'), findsOneWidget);
    // Still running
    expect(find.text('read_file'), findsNothing);
    expect(tester.getTopLeft(find.text('search_code')).dy, lessThan(tester.getTopLeft(find.text('grep')).dy));

    expect(_value(tester, 'Tools, summed'), '1.9s');
    // 1.5s of the first two together, and the 50ms of the third
    expect(_value(tester, 'Tools, real time'), '1.5s');
  });

  testWidgets('says so when the time of the language model was not measured', (tester) async {
    await _openSheet(tester, _answer(took: const Duration(milliseconds: 40)));

    expect(find.text('Language model'), findsNothing);
    expect(find.text('Output speed'), findsNothing);
    expect(_value(tester, 'Total'), '<0.1s');
    expect(find.textContaining('was not measured'), findsOneWidget);
  });

  testWidgets('counts the total up while the answer is generating', (tester) async {
    await _openSheet(
      tester,
      MessageDto(
        id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000001'),
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.generating,
        toolCalls: const [],
        // Long enough ago that the test itself doesn't reach the next minute
        createdAt: DateTime.now().subtract(const Duration(minutes: 3, seconds: 10)),
      ),
    );

    expect(_value(tester, 'Total'), startsWith('3m '));
    // Not yet, as the first response may still come
    expect(find.textContaining('was not measured'), findsNothing);

    // Closing it stops the timer
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Duration'), findsNothing);
  });
}
