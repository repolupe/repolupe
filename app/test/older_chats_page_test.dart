import 'package:app/gen/strings.g.dart';
import 'package:app/pages/older_chats_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/rust.dart';

/// The id of the chat [index], from the newest.
UuidValue _chatId(int index) => UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-${index.toString().padLeft(12, '0')}');

ChatDto _chat(int index) => ChatDto(
  id: _chatId(index),
  title: 'Chat $index',
  allRepositories: true,
  repositoryIds: const [],
  temporary: false,
  createdAt: DateTime.utc(2026, 10, 21, 12),
  updatedAt: DateTime.utc(2026, 10, 21, 12),
);

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the older chats start after the cursor, load more at the end, and a tapped one is opened', (tester) async {
    // The pages listed, by their limit and cursor.
    final requests = <(int, String?)>[];
    final container = RefenaContainer(
      overrides: [
        apiProvider.overrideWithActions((mock) {
          mock.on<ApiListChatsAction>((state, action) {
            requests.add((action.limit, action.cursor));
            return switch (action.cursor) {
              // The drawer showed chats 0 to 9.
              'drawer' => (state, ChatPageDto(items: [for (var i = 10; i < 60; i++) _chat(i)], nextCursor: 'second')),
              'second' => (state, ChatPageDto(items: [for (var i = 60; i < 62; i++) _chat(i)])),
              _ => throw apiError(ErrorCode.notFound, status: 404),
            };
          });
          mock.on<ApiGetChatAction>((state, action) {
            if (action.chatId != _chatId(61)) {
              throw apiError(ErrorCode.notFound, status: 404);
            }
            return (state, ChatDetailDto(chat: _chat(61), messages: const []));
          });
        }),
      ],
    );
    container.redux(apiProvider).dispatch(ApiSetAccountAction(fakeAccount(userId: '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12')));

    await tester.pumpWidget(
      RefenaScope.withContainer(
        container: container,
        child: TranslationProvider(
          child: MaterialApp(
            navigatorKey: container.read(navigationProvider).key,
            scaffoldMessengerKey: container.read(snackBarProvider).key,
            home: const Scaffold(body: Text('Chat page')),
          ),
        ),
      ),
    );
    // ignore: unawaited_futures
    container.global.dispatchAsync(NavigateAction.push(const OlderChatsPage(cursor: 'drawer')));
    await tester.pumpAndSettle();

    expect(find.text('Chat 10'), findsOneWidget);
    expect(requests, [(50, 'drawer')]);
    expect(find.text('Older Chats'), findsOneWidget);

    // The end of the list loads the rest, then there is nothing more to load.
    await tester.scrollUntilVisible(find.text('Chat 59'), 500, scrollable: find.byType(Scrollable));
    await tester.drag(find.byKey(const ValueKey('olderChats.list')), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Chat 61'), findsOneWidget);
    expect(requests, [(50, 'drawer'), (50, 'second')]);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Tapping a chat goes back and opens it.
    await tester.ensureVisible(find.text('Chat 61'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat 61'));
    await tester.pumpAndSettle();
    expect(find.text('Chat page'), findsOneWidget);
    expect(container.read(chatProvider).chat?.title, 'Chat 61');
  });
}
