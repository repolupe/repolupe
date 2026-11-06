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
  allMcpServers: true,
  mcpServerIds: const [],
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
    // The first is the list's, the search field has one too.
    await tester.scrollUntilVisible(find.text('Chat 59'), 500, scrollable: find.byType(Scrollable).first);
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

  testWidgets('a search lists the chats found in pages, and clearing it lists the older chats again', (tester) async {
    // The pages listed, by their query (`null` for the older chats) and cursor.
    final requests = <(String?, String?)>[];
    final container = RefenaContainer(
      overrides: [
        apiProvider.overrideWithActions((mock) {
          mock.on<ApiListChatsAction>((state, action) {
            requests.add((null, action.cursor));
            return (state, ChatPageDto(items: [_chat(70)]));
          });
          mock.on<ApiSearchChatsAction>((state, action) {
            requests.add((action.query, action.cursor));
            return switch ((action.query, action.cursor)) {
              ('sync', null) => (state, ChatPageDto(items: [for (var i = 0; i < 50; i++) _chat(i)], nextCursor: 'second')),
              ('sync', 'second') => (state, ChatPageDto(items: [_chat(50)])),
              ('nothing', null) => (state, const ChatPageDto(items: [])),
              _ => throw apiError(ErrorCode.notFound, status: 404),
            };
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
            home: const OlderChatsPage(cursor: 'drawer'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chat 70'), findsOneWidget);
    expect(requests, [(null, 'drawer')]);

    // The keyboard's search action searches all chats, from the newest.
    await tester.enterText(find.byKey(const ValueKey('olderChats.search')), ' sync ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Chat 70'), findsNothing);
    expect(find.text('Chat 0'), findsOneWidget);
    expect(requests, [(null, 'drawer'), ('sync', null)]);

    await tester.scrollUntilVisible(find.text('Chat 49'), 500, scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byKey(const ValueKey('olderChats.list')), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Chat 50'), findsOneWidget);
    expect(requests, [(null, 'drawer'), ('sync', null), ('sync', 'second')]);

    // So does the button.
    await tester.scrollUntilVisible(find.byKey(const ValueKey('olderChats.search')), -500, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('olderChats.search')), 'nothing');
    await tester.tap(find.byKey(const ValueKey('olderChats.searchButton')));
    await tester.pumpAndSettle();
    expect(find.text('No chats found'), findsOneWidget);
    expect(find.text('Chat 0'), findsNothing);
    expect(requests.last, ('nothing', null));

    await tester.tap(find.byKey(const ValueKey('olderChats.clear')));
    await tester.pumpAndSettle();
    expect(find.text('nothing'), findsNothing);
    expect(find.byKey(const ValueKey('olderChats.clear')), findsNothing);
    expect(find.text('Chat 70'), findsOneWidget);
    expect(find.text('No chats found'), findsNothing);
    expect(requests.last, (null, 'drawer'));
  });
}
