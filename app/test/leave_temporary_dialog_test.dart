import 'package:app/gen/strings.g.dart';
import 'package:app/pages/chat_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/src/rust/third_party/repolupe/dto/mcp.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
final _temporaryId = UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000001');
final _savedId = UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000002');

ChatDto _chat(UuidValue id, String title, {required bool temporary}) => ChatDto(
  id: id,
  title: title,
  allRepositories: false,
  repositoryIds: const [],
  allMcpServers: true,
  mcpServerIds: const [],
  temporary: temporary,
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

/// The chat page, whose drawer lists the saved chat, after sending a question in a new temporary chat.
Future<RefenaContainer> _startTemporaryChat(WidgetTester tester) async {
  final container = RefenaContainer(
    overrides: [
      apiProvider.overrideWithActions((mock) {
        mock.on<ApiListModelsAction>((state, action) => (state, const <ModelDto>[]));
        mock.on<ApiGetMeAction>((state, action) => (state, fakeUser(id: _userId)));
        mock.on<ApiListRepositoriesAction>((state, action) => (state, const <RepositoryDto>[]));
        mock.on<ApiListMcpServersAction>((state, action) => (state, const <McpServerDto>[]));
        mock.on<ApiListChatsAction>((state, action) => (state, ChatPageDto(items: [_chat(_savedId, 'Saved chat', temporary: false)])));
        mock.on<ApiCreateChatAction>((state, action) {
          expect(action.temporary, isTrue);
          return (state, ChatDetailDto(chat: _chat(_temporaryId, 'Temporary chat', temporary: true), messages: _messages(action.content)));
        });
        mock.on<ApiGetChatAction>((state, action) {
          if (action.chatId != _savedId) {
            throw apiError(ErrorCode.notFound, status: 404);
          }
          return (state, ChatDetailDto(chat: _chat(_savedId, 'Saved chat', temporary: false), messages: _messages('Earlier')));
        });
      }),
    ],
  );
  container.redux(apiProvider).dispatch(ApiSetAccountAction(fakeAccount(userId: _userId)));

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

  await tester.tap(find.byKey(const ValueKey('chat.temporary')));
  await tester.enterText(find.byKey(const ValueKey('chat.input')), 'A question');
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('chat.send')));
  await tester.pumpAndSettle();
  expect(container.read(chatProvider).chat?.id, _temporaryId);
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('a new chat asks before leaving a temporary chat, and the chat stays on cancel', (tester) async {
    final container = await _startTemporaryChat(tester);

    await tester.tap(find.byKey(const ValueKey('chat.newChat')));
    await tester.pumpAndSettle();
    expect(find.text('Leave temporary chat?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat.leaveTemporary.cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Leave temporary chat?'), findsNothing);
    expect(container.read(chatProvider).chat?.id, _temporaryId);

    await tester.tap(find.byKey(const ValueKey('chat.newChat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat.leaveTemporary.leave')));
    await tester.pumpAndSettle();
    final state = container.read(chatProvider);
    expect(state.chat, isNull);
    expect(state.isTemporary, isFalse);

    // The drawer's "New chat" asks too.
    await tester.tap(find.byKey(const ValueKey('chat.temporary')));
    await tester.enterText(find.byKey(const ValueKey('chat.input')), 'Another question');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat.send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat.drawer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat.drawer.newChat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat.leaveTemporary.leave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat.drawer.chats')), findsNothing);
    expect(container.read(chatProvider).chat, isNull);
  });

  testWidgets('opening another chat asks before leaving a temporary chat, and the drawer stays open on cancel', (tester) async {
    final container = await _startTemporaryChat(tester);

    await tester.tap(find.byKey(const ValueKey('chat.drawer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved chat'));
    await tester.pumpAndSettle();
    expect(find.text('Leave temporary chat?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat.leaveTemporary.cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat.drawer.chats')), findsOneWidget);
    expect(container.read(chatProvider).chat?.id, _temporaryId);

    await tester.tap(find.text('Saved chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat.leaveTemporary.leave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat.drawer.chats')), findsNothing);
    expect(container.read(chatProvider).chat?.id, _savedId);

    // A chat that is not temporary is left without asking.
    await tester.tap(find.byKey(const ValueKey('chat.newChat')));
    await tester.pumpAndSettle();
    expect(find.text('Leave temporary chat?'), findsNothing);
    expect(container.read(chatProvider).chat, isNull);
  });
}
