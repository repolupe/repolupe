import 'package:app/gen/strings.g.dart';
import 'package:app/pages/raw_answer_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/chat/message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/rust.dart';

final _chatId = UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000000');

MessageDto _message(int n, MessageRole role, String content) => MessageDto(
  id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-00000000000$n'),
  role: role,
  content: content,
  status: MessageStatus.completed,
  toolCalls: const [],
  createdAt: DateTime.utc(2026, 11, 6, 12),
  finishedAt: role == MessageRole.assistant ? DateTime.utc(2026, 11, 6, 12, 1) : null,
);

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('switching how the tables of an answer are laid out keeps its top in place, without a frame in between', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final long = List.filled(40, 'A paragraph that takes up some room.').join('\n\n');
    final cell = 'word ' * 30;
    final table = '| A | B |\n| - | - |\n| $cell | $cell |\n| $cell | $cell |';
    final answer = _message(4, MessageRole.assistant, 'Before the table\n\n$table\n\nAfter the table');
    final messages = [
      _message(1, MessageRole.user, 'First'),
      _message(2, MessageRole.assistant, long),
      _message(3, MessageRole.user, 'Second'),
      answer,
      _message(5, MessageRole.user, 'Third'),
      _message(6, MessageRole.assistant, long),
    ];

    final container = (await tester.runAsync(() => mockContainer(account: fakeAccount(userId: 'user'))))!;
    await tester.pumpWidget(
      RefenaScope.withContainer(
        container: container,
        child: TranslationProvider(
          child: MaterialApp(
            home: Scaffold(
              body: MessageList(chatId: _chatId, messages: messages),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scrolled up until the menu is in the middle, with content above and below. The list is reversed, so scrolling
    // forward moves its content down.
    final list = find.byKey(const ValueKey('chat.messages'));
    final menu = find.byKey(ValueKey('chat.message.${answer.id}.menu'));
    final item = find.byKey(ValueKey('chat.message.${answer.id}.tableLayout'));
    await tester.dragUntilVisible(menu, list, const Offset(0, 100));
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first).position;
    position.jumpTo(position.pixels + 300 - tester.getTopLeft(menu).dy);
    await tester.pumpAndSettle();
    const top = 300.0;
    expect(tester.getTopLeft(menu).dy, moreOrLessEquals(top));
    expect(position.pixels, lessThan(position.maxScrollExtent));

    final texts = t.flutter.chat.assistantMessage;
    final tableHeight = tester.getSize(find.byType(Table)).height;
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text(texts.scrollTables), findsOneWidget);
    await tester.tap(item);
    await tester.pump();
    expect(tester.getSize(find.byType(Table)).height, isNot(tableHeight));
    expect(tester.getTopLeft(menu).dy, moreOrLessEquals(top));
    await tester.pumpAndSettle();

    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text(texts.fitTables), findsOneWidget);
    await tester.tap(item);
    await tester.pump();
    expect(tester.getSize(find.byType(Table)).height, tableHeight);
    expect(tester.getTopLeft(menu).dy, moreOrLessEquals(top));
  });

  testWidgets('the menu of a finished answer opens its raw answer, and has nothing about tables without one', (tester) async {
    final answer = _message(2, MessageRole.assistant, 'An answer');
    final generating = MessageDto(
      id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000004'),
      role: MessageRole.assistant,
      content: 'Still',
      status: MessageStatus.generating,
      toolCalls: const [],
      createdAt: DateTime.utc(2026, 11, 6, 12),
    );
    final messages = [_message(1, MessageRole.user, 'First'), answer, _message(3, MessageRole.user, 'Second'), generating];

    final loaded = <(UuidValue, UuidValue)>[];
    final container = (await tester.runAsync(
      () => mockContainer(
        account: fakeAccount(userId: 'user'),
        api: (mock) {
          mock.on<ApiGetRawAnswerAction>((state, action) {
            loaded.add((action.chatId, action.messageId));
            return (state, const RawAnswerDto(system: 'You answer questions.', tools: [], messages: []));
          });
        },
      ),
    ))!;
    await tester.pumpWidget(
      RefenaScope.withContainer(
        container: container,
        child: TranslationProvider(
          child: MaterialApp(
            navigatorKey: container.read(navigationProvider).key,
            home: Scaffold(
              body: MessageList(chatId: _chatId, messages: messages),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The raw answer is stored once the answer is finished.
    expect(find.byKey(ValueKey('chat.message.${generating.id}.menu')), findsNothing);

    await tester.tap(find.byKey(ValueKey('chat.message.${answer.id}.menu')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(ValueKey('chat.message.${answer.id}.tableLayout')), findsNothing);

    await tester.tap(find.byKey(ValueKey('chat.message.${answer.id}.raw')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RawAnswerPage), findsOneWidget);
    expect(loaded, [(_chatId, answer.id)]);
  });

  testWidgets('a generating answer keeps the label of its last tool call until text follows it', (tester) async {
    MessageDto generating(String content, List<ToolCallStatus> toolCalls) => MessageDto(
      id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000002'),
      role: MessageRole.assistant,
      content: content,
      status: MessageStatus.generating,
      toolCalls: [
        for (final (n, status) in toolCalls.indexed)
          ToolCallSummaryDto(
            id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-00000000010$n'),
            name: 'mcp__banking__list_accounts',
            input: '{}',
            status: status,
            createdAt: DateTime.utc(2026, 11, 6, 12),
          ),
      ],
      createdAt: DateTime.utc(2026, 11, 6, 12),
    );

    final container = (await tester.runAsync(() => mockContainer(account: fakeAccount(userId: 'user'))))!;
    Future<void> show(MessageDto answer) async {
      await tester.pumpWidget(
        RefenaScope.withContainer(
          container: container,
          child: TranslationProvider(
            child: MaterialApp(
              home: Scaffold(
                body: MessageList(chatId: _chatId, messages: [_message(1, MessageRole.user, 'First'), answer]),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    final label = find.text('${t.base.chat.toolCallList.running}…');

    // The preamble alone has no label, only the spinner below it.
    await show(generating('Let me look.', []));
    expect(label, findsNothing);

    await show(generating('Let me look.', [ToolCallStatus.running]));
    expect(label, findsOneWidget);

    // A finished call keeps its label while the model thinks, also when the next call has finished too.
    await show(generating('Let me look.', [ToolCallStatus.completed]));
    expect(label, findsOneWidget);
    await show(generating('Let me look.', [ToolCallStatus.completed, ToolCallStatus.completed]));
    expect(label, findsOneWidget);

    // Text after the call replaces the label, until the next call.
    await show(generating('Let me look.\n\nAll of them', [ToolCallStatus.completed, ToolCallStatus.completed]));
    expect(label, findsNothing);
    await show(
      generating('Let me look.\n\nAll of them', [ToolCallStatus.completed, ToolCallStatus.completed, ToolCallStatus.completed]),
    );
    expect(label, findsOneWidget);
  });
}
