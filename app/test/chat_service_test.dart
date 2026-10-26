import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/model/account.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/chat_list_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/message_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/format.dart';
import 'package:app/util/tool_call.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/rust.dart';

const _chatId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';
const _userMessageId = '0199a8d4-6d5e-7c3a-9b1f-000000000002';
const _answerId = '0199a8d4-6d5e-7c3a-9b1f-000000000003';
const _modelId = '0199a8d4-6d5e-7c3a-9b1f-000000000004';
const _otherModelId = '0199a8d4-6d5e-7c3a-9b1f-000000000005';
const _repositoryId = '0199a8d4-6d5e-7c3a-9b1f-000000000006';
const _toolCallId = '0199a8d4-6d5e-7c3a-9b1f-000000000007';

Map<String, dynamic> _toolCall({
  String id = _toolCallId,
  required String name,
  required Map<String, dynamic> input,
  String status = 'COMPLETED',
}) => {
  'id': id,
  'name': name,
  'input': input,
  'repository_id': _repositoryId,
  'commit_sha': 'abc123',
  'status': status,
  'created_at': '2026-10-21T12:00:30+00:00',
};

ToolCallSummaryDto _toolCallDto(String id, String name, Map<String, dynamic> input, {ToolCallStatus status = ToolCallStatus.completed}) {
  return ToolCallSummaryDto(
    id: UuidValue.fromString(id),
    name: name,
    input: jsonEncode(input),
    repositoryId: UuidValue.fromString(_repositoryId),
    status: status,
    createdAt: DateTime.utc(2026, 10, 21),
  );
}

MessageDto _messageDto(List<ToolCallSummaryDto> toolCalls) {
  return MessageDto(
    id: UuidValue.fromString(_answerId),
    role: MessageRole.assistant,
    content: '',
    status: MessageStatus.completed,
    toolCalls: toolCalls,
    createdAt: DateTime.utc(2026, 10, 21),
  );
}

Map<String, dynamic> _message({
  required String id,
  required String role,
  required String content,
  String status = 'COMPLETED',
  bool finished = false,
  List<Map<String, dynamic>> toolCalls = const [],
}) => {
  'id': id,
  'role': role,
  'content': content,
  'status': status,
  'error': null,
  'model_id': role == 'ASSISTANT' ? _modelId : null,
  'tool_calls': toolCalls,
  'created_at': '2026-10-21T12:00:00+00:00',
  'finished_at': finished ? '2026-10-21T12:01:05+00:00' : null,
  'usage': finished ? {'input_tokens': 10, 'output_tokens': 5, 'cache_read_tokens': 0, 'cache_write_tokens': 0} : null,
  'cost': finished ? {'amount': '0.0042', 'currency': 'USD'} : null,
  'attachment': null,
};

const _user = {
  'id': '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12',
  'role': 'USER',
  'user_name': 'alice',
  'email': null,
  'can_login': true,
  'can_manage_repositories': true,
  'can_change_identity': true,
  'must_change_password': false,
  'auto_commit': false,
  'default_model_id': _otherModelId,
  'locale': null,
  'full_name': null,
  'first_name': null,
  'about': null,
  'created_at': '2026-10-21T12:00:00+00:00',
};

const _repository = {
  'id': _repositoryId,
  'owner_id': '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12',
  'name': 'docs',
  'description': null,
  'remote_url': 'https://git.example.com/docs.git',
  'branch': 'main',
  'poll_interval_seconds': 3600,
  'token': null,
  'allow_commits': false,
  'can_commit': false,
  'sync_status': 'READY',
  'sync_started_at': null,
  'head_commit_sha': null,
  'last_synced_at': null,
  'git_size': null,
  'lfs_size': null,
  'last_error': null,
  'next_sync_at': '2026-10-21T13:00:00+00:00',
  'created_at': '2026-10-21T12:00:00+00:00',
  'updated_at': '2026-10-21T12:00:00+00:00',
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initRustLib();
  });

  test('a new chat is created with the chosen repositories and model, temporary, and its answer is followed across a broken stream', () async {
    final requests = <(String, String, Map<String, dynamic>?)>[];
    var streams = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final text = await utf8.decodeStream(request);
      requests.add((request.method, request.uri.path, text.isEmpty ? null : jsonDecode(text) as Map<String, dynamic>));
      final response = request.response;
      switch (request.uri.path) {
        case '/api/v1/models':
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode([
              {'id': _modelId, 'display_name': 'Claude', 'provider_id': _modelId, 'provider_name': 'Anthropic', 'is_default': true},
              {'id': _otherModelId, 'display_name': 'Haiku', 'provider_id': _modelId, 'provider_name': 'Anthropic', 'is_default': false},
            ]),
          );
        case '/api/v1/me':
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(_user));
        case '/api/v1/repositories':
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode([_repository]));
        case '/api/v1/chats':
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode({
              'id': _chatId,
              'title': 'Hello',
              'all_repositories': false,
              'repository_ids': <Object>[],
              'model_id': null,
              'temporary': true,
              'created_at': '2026-10-21T12:00:00+00:00',
              'updated_at': '2026-10-21T12:00:00+00:00',
              'messages': [
                _message(id: _userMessageId, role: 'USER', content: 'Hello'),
                _message(id: _answerId, role: 'ASSISTANT', content: '', status: 'GENERATING'),
              ],
            }),
          );
        case '/api/v1/chats/$_chatId/messages/$_answerId/stream':
          streams++;
          response.headers.contentType = ContentType('text', 'event-stream');
          final generating = _message(id: _answerId, role: 'ASSISTANT', content: streams == 1 ? '' : 'Hi', status: 'GENERATING');
          response.write('event: snapshot\ndata: ${jsonEncode(generating)}\n\n');
          response.write('event: content_delta\ndata: ${jsonEncode({'text': streams == 1 ? 'Hi' : ' there'})}\n\n');
          // The first stream breaks off without `done`, the client subscribes again.
          if (streams > 1) {
            final done = _message(id: _answerId, role: 'ASSISTANT', content: 'Hi there', finished: true);
            response.write('event: done\ndata: ${jsonEncode(done)}\n\n');
          }
        default:
          response.statusCode = 404;
      }
      await response.close();
    });

    final account = Account(
      apiUrl: 'http://127.0.0.1:${server.port}',
      token: 'session-token',
      user: AccountUser(id: '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12', userName: 'alice'),
    );
    final container = RefenaContainer();
    container.redux(apiProvider).dispatch(ApiSetAccountAction(account));
    final chat = container.redux(chatProvider);

    await chat.dispatchAsync(NewChatAction());
    var state = container.read(chatProvider);
    expect(state.modelName(UuidValue.fromString(_modelId)), 'Claude');
    // The user's own model, not the default one.
    expect(state.answeringModel?.displayName, 'Haiku');
    // With repositories, a new chat reads all of them.
    expect(state.scopeAll, isTrue);
    expect(state.repositories.map((r) => r.name), ['docs']);

    chat.dispatch(SetRepositoryScopeAction(all: false, ids: [UuidValue.fromString(_repositoryId)]));
    await chat.dispatchAsync(ChooseModelAction(UuidValue.fromString(_modelId)));
    expect(container.read(chatProvider).answeringModel?.displayName, 'Claude');
    chat.dispatch(SetTemporaryAction(true));
    expect(container.read(chatProvider).isTemporary, isTrue);

    expect(await chat.dispatchAsyncTakeResult(SendMessageAction('Hello')), isTrue);
    final (_, _, body) = requests.firstWhere((r) => r.$2 == '/api/v1/chats');
    expect(body, containsPair('content', 'Hello'));
    expect(body, containsPair('all_repositories', false));
    expect(body, containsPair('repository_ids', [_repositoryId]));
    expect(body, containsPair('model_id', _modelId));
    expect(body, containsPair('temporary', true));

    for (var i = 0; i < 100 && container.read(chatProvider).answer != null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    state = container.read(chatProvider);
    expect(state.chat?.title, 'Hello');
    expect(state.isTemporary, isTrue);
    expect(state.answer, isNull);
    expect(streams, 2);
    expect(state.messages.map((m) => m.content), ['Hello', 'Hi there']);
    final answer = state.messages.last;
    expect(answer.status, MessageStatus.completed);
    expect(answer.finishedAt!.difference(answer.createdAt), const Duration(seconds: 65));
    expect(answer.cost?.amount, '0.0042');
    // The finished answer is in the chat, no longer in the message service.
    expect(container.read(messageProvider), isNull);

    // A new chat drops the previous one.
    await chat.dispatchAsync(NewChatAction());
    expect(container.read(chatProvider).chat, isNull);
    expect(container.read(chatProvider).messages, isEmpty);
    expect(container.read(chatProvider).isTemporary, isFalse);

    // Opened from a repository's page: the new chat reads only that repository.
    await chat.dispatchAsync(NewChatAction(repositoryIds: [UuidValue.fromString(_repositoryId)]));
    expect(container.read(chatProvider).scopeAll, isFalse);
    expect(container.read(chatProvider).scopeIds, [UuidValue.fromString(_repositoryId)]);
  });

  test('a previous chat is listed and opened with its messages, following its answer', () async {
    final requests = <(String, String)>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final chat = {
      'id': _chatId,
      'title': 'Earlier',
      'all_repositories': false,
      'repository_ids': <Object>[],
      'model_id': null,
      'temporary': false,
      'created_at': '2026-10-21T12:00:00+00:00',
      'updated_at': '2026-10-21T12:00:00+00:00',
    };
    server.listen((request) async {
      requests.add((request.method, request.uri.toString()));
      final response = request.response;
      switch (request.uri.path) {
        case '/api/v1/chats':
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode({
              'items': [chat],
              'next_cursor': 'next',
            }),
          );
        case '/api/v1/chats/$_chatId':
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode({
              ...chat,
              'messages': [
                _message(id: _userMessageId, role: 'USER', content: 'Hello'),
                _message(id: _answerId, role: 'ASSISTANT', content: 'Hi', status: 'GENERATING'),
              ],
            }),
          );
        case '/api/v1/chats/$_chatId/messages/$_answerId/stream':
          response.headers.contentType = ContentType('text', 'event-stream');
          final done = _message(id: _answerId, role: 'ASSISTANT', content: 'Hi there', finished: true);
          response.write('event: done\ndata: ${jsonEncode(done)}\n\n');
        default:
          response.statusCode = 404;
      }
      await response.close();
    });

    final account = Account(
      apiUrl: 'http://127.0.0.1:${server.port}',
      token: 'session-token',
      user: AccountUser(id: '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12', userName: 'alice'),
    );
    final container = RefenaContainer();
    container.redux(apiProvider).dispatch(ApiSetAccountAction(account));

    await container.redux(chatListProvider).dispatchAsync(LoadChatsAction(limit: 5));
    expect(requests.last, ('GET', '/api/v1/chats?limit=5'));
    expect(container.read(chatListProvider)!.items.map((c) => c.title), ['Earlier']);
    expect(container.read(chatListProvider)!.nextCursor, 'next');

    await container.redux(chatProvider).dispatchAsync(OpenChatAction(UuidValue.fromString(_chatId)));
    expect(container.read(chatProvider).chat?.title, 'Earlier');
    expect(container.read(chatProvider).loading, isFalse);

    for (var i = 0; i < 100 && container.read(chatProvider).answer != null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final state = container.read(chatProvider);
    expect(state.answer, isNull);
    expect(state.messages.map((m) => m.content), ['Hello', 'Hi there']);
  });

  test('an attached file is uploaded and sent with a blank message, unless removed, too large or no longer available', () async {
    const attachmentId = '0199a8d4-6d5e-7c3a-9b1f-00000000000c';
    final attachment = {
      'id': attachmentId,
      'number': null,
      'file_name': 'Invoice.pdf',
      'content_type': 'application/pdf',
      'size': 3,
      'created_at': '2026-10-21T12:00:00+00:00',
    };
    final uploads = <(Uri, String?, List<int>)>[];
    final bodies = <String, Map<String, dynamic>>{};
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case '/api/v1/attachments':
          final content = await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
          uploads.add((request.uri, request.headers.contentType?.mimeType, content));
          response.statusCode = 201;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(attachment));
        case '/api/v1/chats':
          bodies[request.uri.path] = jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode({
              'id': _chatId,
              'title': 'Invoice.pdf',
              'all_repositories': false,
              'repository_ids': <Object>[],
              'model_id': null,
              'temporary': false,
              'created_at': '2026-10-21T12:00:00+00:00',
              'updated_at': '2026-10-21T12:00:00+00:00',
              'messages': [
                {
                  ..._message(id: _userMessageId, role: 'USER', content: ''),
                  'attachment': {...attachment, 'number': 1},
                },
                _message(id: _answerId, role: 'ASSISTANT', content: 'It is an invoice.', finished: true),
              ],
            }),
          );
        case '/api/v1/chats/$_chatId/messages':
          bodies[request.uri.path] = jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
          response.statusCode = 400;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'code': 'UNKNOWN_ATTACHMENT', 'message': 'Unknown attachment'}));
        default:
          response.statusCode = 404;
      }
      await response.close();
    });

    final account = Account(
      apiUrl: 'http://127.0.0.1:${server.port}',
      token: 'session-token',
      user: AccountUser(id: '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12', userName: 'alice'),
    );
    final container = RefenaContainer();
    container.redux(apiProvider).dispatch(ApiSetAccountAction(account));
    final chat = container.redux(chatProvider);
    await chat.dispatchAsync(NewChatAction());

    // Too large: not uploaded, not even read.
    await chat.dispatchAsync(
      AttachFileAction(fileName: 'huge.pdf', size: maxAttachmentBytes + 1, read: () async => throw StateError('read')),
    );
    expect(container.read(chatProvider).attachment, isNull);

    // Removed while it is uploaded: the finished upload does not bring it back.
    final read = Completer<Uint8List>();
    final removed = chat.dispatchAsync(AttachFileAction(fileName: 'Other.pdf', size: 3, read: () => read.future));
    for (var i = 0; i < 100 && container.read(chatProvider).attachment == null; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(chatProvider).attachment?.fileName, 'Other.pdf');
    expect(container.read(chatProvider).attachment?.uploaded, isNull);
    expect(container.read(chatProvider).canSend(''), isFalse);
    chat.dispatch(RemoveAttachmentAction());
    read.complete(Uint8List.fromList([1, 2, 3]));
    await removed;
    expect(container.read(chatProvider).attachment, isNull);

    await chat.dispatchAsync(AttachFileAction(fileName: 'Invoice.pdf', size: 3, read: () async => Uint8List.fromList([37, 80, 68])));
    expect(container.read(chatProvider).attachment?.uploaded?.id, UuidValue.fromString(attachmentId));
    final (uri, contentType, content) = uploads.last;
    expect(uri.queryParameters, {'file_name': 'Invoice.pdf'});
    expect(contentType, 'application/octet-stream');
    expect(content, [37, 80, 68]);

    // A blank message can be sent with an attachment.
    expect(container.read(chatProvider).canSend(' '), isTrue);
    expect(await chat.dispatchAsyncTakeResult(SendMessageAction(' ')), isTrue);
    expect(bodies['/api/v1/chats'], containsPair('attachment_id', attachmentId));
    var state = container.read(chatProvider);
    expect(state.attachment, isNull);
    expect(state.messages.first.attachment?.fileName, 'Invoice.pdf');
    expect(state.messages.first.attachment?.number, 1);
    expect(state.canSend(' '), isFalse);

    // Removed by the server meanwhile: it has to be attached again.
    await chat.dispatchAsync(AttachFileAction(fileName: 'Invoice.pdf', size: 3, read: () async => Uint8List.fromList([37, 80, 68])));
    expect(await chat.dispatchAsyncTakeResult(SendMessageAction('Again')), isFalse);
    expect(bodies['/api/v1/chats/$_chatId/messages'], containsPair('attachment_id', attachmentId));
    state = container.read(chatProvider);
    expect(state.attachment, isNull);
    expect(state.sending, isFalse);
    expect(state.messages, hasLength(2));
  });

  test('the tool calls of an answer are added and finished as their events arrive', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final finish = Completer<void>();
    final toolCall = _toolCall(name: 'read_file', input: {'repository': 'docs', 'path': 'README.md'}, status: 'RUNNING');
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path != '/api/v1/chats/$_chatId/messages/$_answerId/stream') {
        response.statusCode = 404;
        await response.close();
        return;
      }
      // Sent as they are written, so the client sees the tool call before the answer is done.
      response.bufferOutput = false;
      response.headers.contentType = ContentType('text', 'event-stream');
      response.write('event: snapshot\ndata: ${jsonEncode(_message(id: _answerId, role: 'ASSISTANT', content: '', status: 'GENERATING'))}\n\n');
      response.write('event: tool_call_started\ndata: ${jsonEncode(toolCall)}\n\n');
      response.write('event: tool_call_finished\ndata: ${jsonEncode({'id': _toolCallId, 'status': 'COMPLETED'})}\n\n');
      await response.flush();
      await finish.future;
      final done = _message(
        id: _answerId,
        role: 'ASSISTANT',
        content: 'Hi',
        finished: true,
        toolCalls: [
          {...toolCall, 'status': 'COMPLETED'},
        ],
      );
      response.write('event: done\ndata: ${jsonEncode(done)}\n\n');
      await response.close();
    });

    final account = Account(
      apiUrl: 'http://127.0.0.1:${server.port}',
      token: 'session-token',
      user: AccountUser(id: '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12', userName: 'alice'),
    );
    final container = RefenaContainer();
    container.redux(apiProvider).dispatch(ApiSetAccountAction(account));

    final answer = MessageDto(
      id: UuidValue.fromString(_answerId),
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.generating,
      toolCalls: const [],
      createdAt: DateTime.utc(2026, 10, 21, 12),
    );
    final followed = container
        .redux(messageProvider)
        .dispatchAsyncTakeResult(
          FollowMessageAction(chatId: UuidValue.fromString(_chatId), message: answer),
        );
    for (var i = 0; i < 100 && container.read(messageProvider)?.toolCalls.firstOrNull?.status != ToolCallStatus.completed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final running = container.read(messageProvider)!;
    expect(running.toolCalls.map((t) => (t.name, t.status)), [('read_file', ToolCallStatus.completed)]);
    expect(running.toolCalls.single.path, 'README.md');

    finish.complete();
    final finished = await followed;
    expect(finished?.toolCalls.single.status, ToolCallStatus.completed);
  });

  test('presented files and proposed changes are shown once each, the last change of a file winning', () {
    const second = '0199a8d4-6d5e-7c3a-9b1f-000000000008';
    const third = '0199a8d4-6d5e-7c3a-9b1f-000000000009';
    const fourth = '0199a8d4-6d5e-7c3a-9b1f-00000000000a';
    const fifth = '0199a8d4-6d5e-7c3a-9b1f-00000000000b';
    final message = _messageDto([
      _toolCallDto(_toolCallId, 'present_file_to_user', {'path': './docs//guide.md'}),
      _toolCallDto(second, 'present_file_to_user', {'path': 'docs/guide.md'}),
      _toolCallDto(third, 'change_file', {'path': 'README.md', 'message': 'Fix typo'}),
      _toolCallDto(fourth, 'change_file', {'path': 'README.md', 'message': 'Fix typos'}),
      _toolCallDto(fifth, 'change_file', {'path': 'other.md'}, status: ToolCallStatus.failed),
    ]);
    expect(presentedFiles(message).map((f) => (f.toolCall.id.uuid, f.path)), [(_toolCallId, 'docs/guide.md')]);
    expect(proposedChanges(message).map((c) => (c.toolCall.id.uuid, c.path)), [(fourth, 'README.md')]);

    final moves = _toolCallDto(_toolCallId, 'move_files', {
      'moves': [
        {'from': 'a.md', 'to': 'docs/a.md'},
        {'from': 'b', 'to': 'docs/b'},
      ],
    });
    expect(proposedChanges(_messageDto([moves])).single.path, 'docs/a.md');
    expect(moves.detail, '2 moves');
    expect(fileName('docs/guide.md'), 'guide.md');
    expect(_toolCallDto(_toolCallId, 'grep', {'pattern': 'TODO', 'path': 'src'}).detail, '"TODO" in src');
  });

  test('costs and durations are formatted like the web', () {
    expect(formatCost('0.0042', 'USD'), r'<$0.01');
    expect(formatCost('0.034', 'USD'), r'$0.03');
    expect(formatCost('0', 'USD'), r'$0.00');
    expect(formatCost('1.5', 'EUR'), '€1.50');
    expect(formatCost('abc', 'USD'), 'abc USD');
    expect(formatDuration(const Duration(seconds: 42)), '42s');
    expect(formatDuration(const Duration(seconds: 185)), '3m 05s');
  });
}
