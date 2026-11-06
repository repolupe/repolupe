import 'package:app/gen/strings.g.dart';
import 'package:app/pages/chat_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/src/rust/third_party/repolupe/dto/mcp.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:app/widget/chat/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
final _savedId = UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000001');
final _newId = UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000002');

ChatDto _chat(UuidValue id, String title) => ChatDto(
  id: id,
  title: title,
  allRepositories: false,
  repositoryIds: const [],
  allMcpServers: true,
  mcpServerIds: const [],
  temporary: false,
  createdAt: DateTime.utc(2026, 10, 21, 12),
  updatedAt: DateTime.utc(2026, 10, 21, 12),
);

/// A finished question and answer, so that no answer is followed.
List<MessageDto> _messages(String question) => [
  MessageDto(
    id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000003'),
    role: MessageRole.user,
    content: question,
    status: MessageStatus.completed,
    toolCalls: const [],
    createdAt: DateTime.utc(2026, 10, 21, 12),
  ),
  MessageDto(
    id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000004'),
    role: MessageRole.assistant,
    content: 'The answer',
    status: MessageStatus.completed,
    toolCalls: const [],
    createdAt: DateTime.utc(2026, 10, 21, 12),
    finishedAt: DateTime.utc(2026, 10, 21, 12, 1),
  ),
];

/// The chat page in a window of [size], with the saved chat listed. A new chat is titled after its question and
/// listed first from then on. The panel was hidden before unless [panelVisible].
Future<RefenaContainer> _pumpChatPage(WidgetTester tester, Size size, {bool panelVisible = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final listed = [_chat(_savedId, 'Saved chat')];
  final container = (await tester.runAsync(() async {
    final container = await mockContainer(
      account: fakeAccount(userId: _userId),
      api: (mock) {
        mock.on<ApiListModelsAction>((state, action) => (state, const <ModelDto>[]));
        mock.on<ApiListRepositoriesAction>((state, action) => (state, const <RepositoryDto>[]));
        mock.on<ApiListMcpServersAction>((state, action) => (state, const <McpServerDto>[]));
        mock.on<ApiListChatsAction>((state, action) => (state, ChatPageDto(items: [...listed])));
        mock.on<ApiCreateChatAction>((state, action) {
          final chat = _chat(_newId, action.content);
          listed.insert(0, chat);
          return (state, ChatDetailDto(chat: chat, messages: _messages(action.content)));
        });
        mock.on<ApiGetChatAction>((state, action) {
          if (action.chatId != _savedId) {
            throw apiError(ErrorCode.notFound, status: 404);
          }
          return (state, ChatDetailDto(chat: _chat(_savedId, 'Saved chat'), messages: _messages('Earlier')));
        });
      },
    );
    await container.read(persistenceProvider).setChatPanelVisible(panelVisible);
    return container;
  }))!;

  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          navigatorKey: container.read(navigationProvider).key,
          scaffoldMessengerKey: container.read(snackBarProvider).key,
          home: const ChatPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The chat titled [title] in the list of chats.
Finder _listed(String title) => find.descendant(of: find.byKey(const ValueKey('chat.drawer.chats')), matching: find.text(title));

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('on a wide screen, the chats are a panel beside the chat that stays open and stays current', (tester) async {
    // An iPad in landscape.
    final container = await _pumpChatPage(tester, const Size(1376, 1032));

    expect(find.byKey(const ValueKey('chat.drawer')), findsNothing);
    expect(_listed('Saved chat'), findsOneWidget);
    // Centered beside the panel (304 wide, with the divider), not on the screen.
    expect(tester.getCenter(find.byType(MessageInput)).dx, closeTo(305 + (1376 - 305) / 2, 0.01));

    await tester.tap(_listed('Saved chat'));
    await tester.pumpAndSettle();
    expect(container.read(chatProvider).chat?.id, _savedId);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(_listed('Saved chat'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat.drawer.newChat')));
    await tester.pumpAndSettle();
    expect(container.read(chatProvider).chat, isNull);
    expect(find.byType(ChatPage), findsOneWidget);

    // The new chat is listed once it is created.
    await tester.enterText(find.byKey(const ValueKey('chat.input')), 'A question');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat.send')));
    await tester.pumpAndSettle();
    expect(container.read(chatProvider).chat?.id, _newId);
    expect(_listed('A question'), findsOneWidget);
    expect(_listed('Saved chat'), findsOneWidget);
  });

  testWidgets('on a wide screen, the panel is hidden and shown again, and stays when a chat is opened', (tester) async {
    final container = await _pumpChatPage(tester, const Size(1376, 1032));
    final persistence = container.read(persistenceProvider);
    final button = find.byKey(const ValueKey('chat.panel'));
    // At the end of the panel's header, in the middle of the space it leaves.
    expect(tester.getCenter(button), const Offset(304 - 28, 28));

    await tester.tap(button);
    // It moves with the panel.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getCenter(button).dx, inExclusiveRange(28, 304 - 28));
    await tester.pumpAndSettle();
    expect(_listed('Saved chat').hitTestable(), findsNothing);
    // The chat takes the whole width, and the button is in its app bar.
    expect(tester.getCenter(find.byType(MessageInput)).dx, closeTo(1376 / 2, 0.01));
    expect(tester.getCenter(button), const Offset(28, 28));
    expect(persistence.getChatPanelVisible(), isFalse);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.getCenter(button), const Offset(304 - 28, 28));
    expect(persistence.getChatPanelVisible(), isTrue);
    await tester.tap(_listed('Saved chat'));
    await tester.pumpAndSettle();
    expect(container.read(chatProvider).chat?.id, _savedId);
    expect(_listed('Saved chat').hitTestable(), findsOneWidget);
    expect(tester.getCenter(button), const Offset(304 - 28, 28));
  });

  testWidgets('on a wide screen, a panel hidden before stays hidden', (tester) async {
    await _pumpChatPage(tester, const Size(1376, 1032), panelVisible: false);

    expect(_listed('Saved chat').hitTestable(), findsNothing);
    expect(tester.getCenter(find.byType(MessageInput)).dx, closeTo(1376 / 2, 0.01));
    expect(tester.getCenter(find.byKey(const ValueKey('chat.panel'))), const Offset(28, 28));
  });

  testWidgets('on a phone in landscape, the chats stay in the drawer', (tester) async {
    await _pumpChatPage(tester, const Size(956, 440));

    expect(find.byKey(const ValueKey('chat.drawer.chats')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chat.drawer')));
    await tester.pumpAndSettle();
    expect(_listed('Saved chat'), findsOneWidget);
  });
}
