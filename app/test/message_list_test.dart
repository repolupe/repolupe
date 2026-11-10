import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/chat/message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    // Scrolled up until the button is in the middle, with content above and below. The list is reversed, so scrolling
    // forward moves its content down.
    final list = find.byKey(const ValueKey('chat.messages'));
    final button = find.byKey(ValueKey('chat.message.${answer.id}.tableLayout'));
    await tester.dragUntilVisible(button, list, const Offset(0, 100));
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first).position;
    position.jumpTo(position.pixels + 300 - tester.getTopLeft(button).dy);
    await tester.pumpAndSettle();
    const top = 300.0;
    expect(tester.getTopLeft(button).dy, moreOrLessEquals(top));
    expect(position.pixels, lessThan(position.maxScrollExtent));

    final texts = t.flutter.chat.assistantMessage;
    await tester.tap(button);
    await tester.pump();
    expect(find.byTooltip(texts.fitTables), findsOneWidget);
    expect(tester.getTopLeft(button).dy, moreOrLessEquals(top));

    await tester.tap(button);
    await tester.pump();
    expect(find.byTooltip(texts.scrollTables), findsOneWidget);
    expect(tester.getTopLeft(button).dy, moreOrLessEquals(top));
  });
}
