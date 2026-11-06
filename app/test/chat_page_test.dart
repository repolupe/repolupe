import 'package:app/gen/strings.g.dart';
import 'package:app/pages/chat_page.dart';
import 'package:app/pages/settings/admin/llm_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/instance.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/src/rust/third_party/repolupe/dto/mcp.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/widget/chat/greeting_hero.dart';
import 'package:app/widget/chat/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/fake_user.dart';
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

/// The chat page in a window of [size] on the server `Acme Docs`, with the saved chat listed. A new chat is titled
/// after its question and listed first from then on. The panel was hidden before unless [panelVisible]. The [user] is
/// loaded, if given. The server has the [models], none by default.
Future<RefenaContainer> _pumpChatPage(
  WidgetTester tester,
  Size size, {
  bool panelVisible = true,
  UserDto? user,
  List<ModelDto> models = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final listed = [_chat(_savedId, 'Saved chat')];
  final container = (await tester.runAsync(() async {
    final container = await mockContainer(
      account: fakeAccount(userId: _userId),
      api: (mock) {
        // Async, since the app bar loads it while building.
        mock.on<ApiGetInstanceAction>((state, action) async => (state, InstanceDto(name: 'Acme Docs')));
        mock.on<ApiListModelsAction>((state, action) => (state, models));
        mock.on<ApiListLlmProvidersAction>((state, action) => (state, const <LlmProviderDto>[]));
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
    if (user != null) {
      container.redux(meProvider).dispatch(SetMeAction(user));
    }
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

/// [title] in the chat's app bar.
Finder _appBarTitle(String title) => find.descendant(of: find.byType(AppBar), matching: find.text(title));

/// An iPhone in portrait.
const _phone = Size(402, 874);

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

  testWidgets('a new chat greets the user by the time of day and their first name, with the server name as its title', (tester) async {
    await _pumpChatPage(
      tester,
      _phone,
      user: fakeUser(id: _userId, firstName: 'Alice'),
    );

    expect(_appBarTitle('Acme Docs'), findsOneWidget);
    final greeting = switch (DayTime.of(DateTime.now())) {
      DayTime.night => 'Hello Alice',
      DayTime.morning => 'Good morning Alice',
      DayTime.day => 'Good afternoon Alice',
      DayTime.evening => 'Good evening Alice',
    };
    expect(find.text(greeting), findsOneWidget);

    // Once created, the chat has its own title.
    await tester.enterText(find.byKey(const ValueKey('chat.input')), 'A question');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat.send')));
    await tester.pumpAndSettle();
    expect(_appBarTitle('A question'), findsOneWidget);
    expect(_appBarTitle('Acme Docs'), findsNothing);
  });

  testWidgets('a new chat asks a user without a first name what they would like to know', (tester) async {
    await _pumpChatPage(tester, _phone, user: fakeUser(id: _userId));

    expect(find.text('What would you like to know?'), findsOneWidget);
  });

  testWidgets('without a model, an admin can add an LLM provider below the greeting', (tester) async {
    await _pumpChatPage(
      tester,
      _phone,
      user: fakeUser(id: _userId, role: UserRole.admin),
    );

    await tester.tap(find.byKey(const ValueKey('chat.addProvider')));
    await tester.pumpAndSettle();
    expect(find.byType(LlmPage), findsOneWidget);
  });

  testWidgets('without a model, a user is not offered to add an LLM provider', (tester) async {
    await _pumpChatPage(tester, _phone, user: fakeUser(id: _userId));

    expect(find.text('What would you like to know?'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat.addProvider')), findsNothing);
  });

  testWidgets('with a model, an admin is not offered to add an LLM provider', (tester) async {
    await _pumpChatPage(
      tester,
      _phone,
      user: fakeUser(id: _userId, role: UserRole.admin),
      models: [
        fakeModel(
          id: '0199a8d4-6d5e-7c3a-9b1f-000000000005',
          displayName: 'Claude',
          providerId: '0199a8d4-6d5e-7c3a-9b1f-000000000006',
          providerName: 'Anthropic',
          isDefault: true,
        ),
      ],
    );

    expect(find.text('What would you like to know?'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat.addProvider')), findsNothing);
  });
}
