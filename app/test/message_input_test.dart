import 'package:app/gen/strings.g.dart';
import 'package:app/pages/chat_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/attachment.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/src/rust/third_party/repolupe/dto/mcp.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/fake_repository.dart';
import 'support/image_picker.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _docsId = '0199a8d4-6d5e-7c3a-9b1f-000000000011';
const _notesId = '0199a8d4-6d5e-7c3a-9b1f-000000000012';
final _chatId = UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000001');
final _providerId = UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000021');
const _searchId = '0199a8d4-6d5e-7c3a-9b1f-000000000041';
const _issuesId = '0199a8d4-6d5e-7c3a-9b1f-000000000042';

final _models = [
  ModelDto(
    id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000031'),
    displayName: 'Sonnet',
    providerId: _providerId,
    providerName: 'Anthropic',
    isDefault: true,
  ),
  ModelDto(
    id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000032'),
    displayName: 'Opus',
    providerId: _providerId,
    providerName: 'Anthropic',
    isDefault: false,
  ),
];

/// An MCP server of the user with one tool, or shared with them if [shared] is set (whether they turned it on).
McpServerDto _mcpServer({
  required String id,
  required String name,
  bool enabled = true,
  bool? shared,
  McpServerStatus status = McpServerStatus.ready,
  List<String> disabledTools = const [],
}) => McpServerDto(
  id: UuidValue.fromString(id),
  ownerId: UuidValue.fromString(_userId),
  shared: shared == null ? null : McpServerShareDto(ownerName: 'bob', enabled: shared, createdAt: DateTime.utc(2026, 10, 20, 12)),
  name: name,
  url: 'https://mcp.example.com/mcp',
  enabled: enabled,
  auth: McpServerAuth.none,
  status: status,
  tools: const [McpToolDto(name: 'search')],
  disabledTools: disabledTools,
  checkedAt: DateTime.utc(2026, 10, 21, 12),
  createdAt: DateTime.utc(2026, 10, 20, 12),
  updatedAt: DateTime.utc(2026, 10, 21, 12),
);

/// The chat page of a user with [repositories] and [mcpServers], recording the chats it creates in [created] and the
/// files it uploads in [uploaded].
Future<RefenaContainer> _pumpChatPage(
  WidgetTester tester, {
  required List<RepositoryDto> repositories,
  List<McpServerDto> mcpServers = const [],
  List<ApiCreateChatAction>? created,
  List<ApiUploadAttachmentAction>? uploaded,
}) async {
  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: _userId),
      api: (mock) {
        mock.on<ApiListModelsAction>((state, action) => (state, _models));
        mock.on<ApiListRepositoriesAction>((state, action) => (state, repositories));
        mock.on<ApiListMcpServersAction>((state, action) => (state, mcpServers));
        mock.on<ApiCreateChatAction>((state, action) {
          created?.add(action);
          final chat = ChatDto(
            id: _chatId,
            title: 'A question',
            allRepositories: action.allRepositories,
            repositoryIds: action.repositoryIds,
            allMcpServers: action.allMcpServers,
            mcpServerIds: action.mcpServerIds,
            temporary: false,
            createdAt: DateTime.utc(2026, 10, 21, 12),
            updatedAt: DateTime.utc(2026, 10, 21, 12),
          );
          final message = MessageDto(
            id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000003'),
            role: MessageRole.user,
            content: action.content,
            status: MessageStatus.completed,
            toolCalls: const [],
            createdAt: DateTime.utc(2026, 10, 21, 12),
          );
          return (state, ChatDetailDto(chat: chat, messages: [message]));
        });
        mock.on<ApiUploadAttachmentAction>((state, action) {
          uploaded?.add(action);
          final attachment = AttachmentDto(
            id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000051'),
            number: 1,
            fileName: action.fileName,
            contentType: 'image/jpeg',
            size: action.content.length,
            createdAt: DateTime.utc(2026, 10, 21, 12),
          );
          return (state, attachment);
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
          scaffoldMessengerKey: container.read(snackBarProvider).key,
          home: const ChatPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Closes the bottom sheet by tapping its barrier.
Future<void> _closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  final repositories = [
    fakeRepository(id: _docsId, ownerId: _userId, name: 'docs'),
    fakeRepository(id: _notesId, ownerId: _userId, name: 'notes'),
  ];

  testWidgets('the plus button chooses the repositories of a new chat, shown as a chip until the chat is created', (tester) async {
    final created = <ApiCreateChatAction>[];
    final container = await _pumpChatPage(tester, repositories: repositories, created: created);

    // All repositories are the default, which takes no space.
    expect(find.byKey(const ValueKey('chat.repositories')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat.options')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat.options.camera')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat.options.attach')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('chat.options.repositories')), matching: find.text('All Repositories')),
      findsOneWidget,
    );

    // The repository sheet replaces the options.
    await tester.tap(find.byKey(const ValueKey('chat.options.repositories')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat.options.attach')), findsNothing);
    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    await _closeSheet(tester);

    final chip = find.byKey(const ValueKey('chat.repositories'));
    expect(find.descendant(of: chip, matching: find.text('docs')), findsOneWidget);

    // The chip opens the repository sheet again.
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('notes'));
    await tester.pumpAndSettle();
    await _closeSheet(tester);
    expect(find.descendant(of: chip, matching: find.text('2 repositories')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('chat.input')), 'A question');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat.send')));
    await tester.pumpAndSettle();
    expect(created.single.allRepositories, isFalse);
    expect(created.single.repositoryIds, [UuidValue.fromString(_docsId), UuidValue.fromString(_notesId)]);

    // The chat keeps its repositories, so the plus button only offers the camera and attaching a file.
    expect(container.read(chatProvider).chat?.id, _chatId);
    expect(find.byKey(const ValueKey('chat.repositories')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chat.options')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat.options.camera')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat.options.attach')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat.options.repositories')), findsNothing);
  });

  testWidgets('removing the repository chip reads all repositories again', (tester) async {
    final container = await _pumpChatPage(tester, repositories: repositories);
    container.redux(chatProvider).dispatch(SetRepositoryScopeAction(all: false, ids: const []));
    await tester.pumpAndSettle();

    final chip = find.byKey(const ValueKey('chat.repositories'));
    expect(find.descendant(of: chip, matching: find.text('No repository')), findsOneWidget);
    expect(find.descendant(of: chip, matching: find.byIcon(Icons.folder_off_outlined)), findsOneWidget);

    await tester.tap(find.descendant(of: chip, matching: find.byIcon(Icons.clear)));
    await tester.pumpAndSettle();
    expect(container.read(chatProvider).allRepositories, isTrue);
    expect(chip, findsNothing);
  });

  testWidgets('without repositories, the plus button offers the camera and attaching a file', (tester) async {
    await _pumpChatPage(tester, repositories: const []);

    await tester.tap(find.byKey(const ValueKey('chat.options')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat.options.camera')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat.options.attach')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat.options.repositories')), findsNothing);
    expect(find.byKey(const ValueKey('chat.options.mcpServers')), findsNothing);
  });

  testWidgets('the camera attaches the photo it takes, named after the time', (tester) async {
    final uploaded = <ApiUploadAttachmentAction>[];
    final container = await _pumpChatPage(tester, repositories: const [], uploaded: uploaded);
    final content = Uint8List.fromList([255, 216, 255]);
    final camera = FakeImagePicker(photo: XFile.fromData(content, path: '/tmp/image_picker_0199a8d4.jpg'));
    ImagePickerPlatform.instance = camera;

    await tester.tap(find.byKey(const ValueKey('chat.options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat.options.camera')));
    await tester.pumpAndSettle();

    // Scaled down by the picker, so the full resolution is never uploaded
    expect(camera.options?.maxWidth, 2048);
    expect(camera.options?.maxHeight, 2048);
    expect(camera.options?.imageQuality, 85);
    expect(uploaded.single.fileName, matches(RegExp(r'^IMG_\d{8}_\d{6}\.jpg$')));
    expect(uploaded.single.content, content);
    expect(container.read(chatProvider).attachment?.uploaded, isNotNull);
    expect(find.textContaining(uploaded.single.fileName, findRichText: true), findsOneWidget);
  });

  testWidgets('a camera that may not be used says so, and a cancelled photo attaches nothing', (tester) async {
    final container = await _pumpChatPage(tester, repositories: const []);

    ImagePickerPlatform.instance = FakeImagePicker(error: PlatformException(code: 'camera_access_denied'));
    await tester.tap(find.byKey(const ValueKey('chat.options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat.options.camera')));
    await tester.pumpAndSettle();
    expect(find.text('Repolupe may not use the camera. Allow it in the system settings.'), findsOneWidget);

    ImagePickerPlatform.instance = FakeImagePicker();
    await tester.tap(find.byKey(const ValueKey('chat.options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat.options.camera')));
    await tester.pumpAndSettle();
    expect(container.read(chatProvider).attachment, isNull);
  });

  testWidgets('the plus button chooses the MCP servers of a new chat among those that are on', (tester) async {
    final created = <ApiCreateChatAction>[];
    final container = await _pumpChatPage(
      tester,
      repositories: const [],
      mcpServers: [
        _mcpServer(id: _searchId, name: 'Search'),
        _mcpServer(id: _issuesId, name: 'Issues', status: McpServerStatus.authorizationRequired),
        _mcpServer(id: '0199a8d4-6d5e-7c3a-9b1f-000000000043', name: 'Turned off', enabled: false),
        _mcpServer(id: '0199a8d4-6d5e-7c3a-9b1f-000000000044', name: 'Shared, not turned on', shared: false),
        _mcpServer(id: '0199a8d4-6d5e-7c3a-9b1f-000000000045', name: 'Shared, off for its owner', enabled: false, shared: true),
      ],
      created: created,
    );

    await tester.tap(find.byKey(const ValueKey('chat.options')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat.options.repositories')), findsNothing);
    expect(
      find.descendant(of: find.byKey(const ValueKey('chat.options.mcpServers')), matching: find.text('All MCP Servers')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('chat.options.mcpServers')));
    await tester.pumpAndSettle();
    expect(find.text('Turned off'), findsNothing);
    expect(find.text('Shared, not turned on'), findsNothing);
    // The owner turning it off for their chats leaves the user's alone.
    expect(find.text('Shared, off for its owner'), findsOneWidget);
    // Why the model doesn't get its tools for now.
    expect(find.text('Sign-in required'), findsOneWidget);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await _closeSheet(tester);

    final chip = find.byKey(const ValueKey('chat.mcpServers'));
    expect(find.descendant(of: chip, matching: find.text('Search')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('chat.input')), 'A question');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat.send')));
    await tester.pumpAndSettle();
    expect(created.single.allMcpServers, isFalse);
    expect(created.single.mcpServerIds, [UuidValue.fromString(_searchId)]);
    expect(container.read(chatProvider).chat?.id, _chatId);
    expect(chip, findsNothing);
  });

  testWidgets('removing the MCP server chip gives the new chat all servers again', (tester) async {
    final container = await _pumpChatPage(
      tester,
      repositories: const [],
      mcpServers: [
        _mcpServer(id: _searchId, name: 'Search', disabledTools: const ['search']),
      ],
    );
    container.redux(chatProvider).dispatch(SetMcpServerScopeAction(all: false, ids: const []));
    await tester.pumpAndSettle();

    final chip = find.byKey(const ValueKey('chat.mcpServers'));
    expect(find.descendant(of: chip, matching: find.text('No MCP servers')), findsOneWidget);
    expect(find.descendant(of: chip, matching: find.byIcon(Icons.extension_off_outlined)), findsOneWidget);

    // A server with all its tools turned off says so.
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('0 of 1 tool enabled'), findsOneWidget);
    await _closeSheet(tester);

    await tester.tap(find.descendant(of: chip, matching: find.byIcon(Icons.clear)));
    await tester.pumpAndSettle();
    expect(container.read(chatProvider).allMcpServers, isTrue);
    expect(chip, findsNothing);
  });

  testWidgets('without MCP servers that are on, they are not offered and the chat gets all of them', (tester) async {
    final created = <ApiCreateChatAction>[];
    await _pumpChatPage(
      tester,
      repositories: [fakeRepository(id: _docsId, ownerId: _userId, name: 'docs')],
      mcpServers: [_mcpServer(id: _searchId, name: 'Search', enabled: false)],
      created: created,
    );

    await tester.tap(find.byKey(const ValueKey('chat.options')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat.options.repositories')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat.options.mcpServers')), findsNothing);
    await _closeSheet(tester);

    await tester.enterText(find.byKey(const ValueKey('chat.input')), 'A question');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat.send')));
    await tester.pumpAndSettle();
    expect(created.single.allMcpServers, isTrue);
  });

  testWidgets('the model next to the send button opens the sheet to choose another', (tester) async {
    final container = await _pumpChatPage(tester, repositories: const []);

    final button = find.byKey(const ValueKey('chat.model'));
    expect(find.descendant(of: button, matching: find.text('Sonnet')), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opus'));
    await tester.pumpAndSettle();
    expect(container.read(chatProvider).modelId, _models[1].id);
    expect(find.descendant(of: button, matching: find.text('Opus')), findsOneWidget);
  });
}
