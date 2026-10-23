import 'dart:async';
import 'dart:io';

import 'package:app/src/rust/api/client.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/api/local.dart';
import 'package:app/src/rust/api/simple.dart';
import 'package:app/src/rust/api/stream.dart';
import 'package:app/src/rust/third_party/repolupe/dto/auth.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/rust.dart';

void main() {
  setUpAll(initRustLib);

  test('greet calls into Rust', () {
    expect(greet(name: 'Tom'), 'Hello, Tom!');
  });

  test('client errors are typed exceptions', () async {
    expect(() => Client.remote(baseUrl: 'example.com'), throwsA(isA<ClientError_Transport>()));

    // Port 1 is reserved, nothing listens there.
    final client = Client.remote(baseUrl: 'http://127.0.0.1:1', token: 'token');
    expect(client.token(), 'token');
    client.setToken(token: null);
    expect(client.token(), isNull);
    await expectLater(client.instance(), throwsA(isA<ClientError_Transport>()));
  });

  test('a local instance starts, logs in and shuts down', () async {
    final dir = await Directory.systemTemp.createTemp('repolupe_local_');
    addTearDown(() => dir.delete(recursive: true));
    final password = generateSecret();
    final config = LocalConfig(dataDir: dir.path, tokenEncryptionKey: generateSecret(), adminPassword: password);
    await expectLater(
      startLocal(
        config: LocalConfig(dataDir: dir.path, tokenEncryptionKey: 'short', adminPassword: password),
      ),
      throwsA(isA<LocalError>()),
    );

    final local = await startLocal(config: config);
    final client = Client.local(instance: local);
    final response = await client.login(
      request: LoginRequest(userNameOrEmail: localAdminUserName(), password: password),
    );
    expect(response.user.mustChangePassword, isFalse);
    expect(client.token(), response.token);
    expect((await client.me()).userName, localAdminUserName());

    await local.shutdown();
    expect(local.isRunning(), isFalse);
    await expectLater(client.me(), throwsA(isA<ClientError_Transport>()));
  });

  test('message streams deliver typed events and can be cancelled', () async {
    // An LLM API that never answers, so the answer stays generating until it is cancelled.
    final llm = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => llm.close(force: true));
    llm.listen((_) {});
    final dir = await Directory.systemTemp.createTemp('repolupe_stream_');
    addTearDown(() => dir.delete(recursive: true));
    final password = generateSecret();
    final local = await startLocal(
      config: LocalConfig(dataDir: dir.path, tokenEncryptionKey: generateSecret(), adminPassword: password),
    );
    addTearDown(local.shutdown);
    final client = Client.local(instance: local);
    await client.login(
      request: LoginRequest(userNameOrEmail: localAdminUserName(), password: password),
    );
    final provider = await client.createLlmProvider(
      request: CreateLlmProviderRequest(name: 'Mock', apiFormat: LlmApiFormat.anthropic, baseUrl: 'http://127.0.0.1:${llm.port}'),
    );
    await client.createLlmModel(
      providerId: provider.id,
      request: const LlmModelRequest(apiName: 'mock-model'),
    );
    final chat = await client.createChat(request: const CreateChatRequest(content: 'Hello', allRepositories: true, temporary: false));
    final chatId = chat.chat.id;
    final answerId = chat.messages.last.id;

    // Errors before the stream starts are thrown.
    await expectLater(
      client.streamMessage(chatId: chatId, messageId: chatId, cancel: CancellationToken()),
      throwsA(isA<ClientError_Api>().having((e) => e.code, 'code', ErrorCode.notFound)),
    );

    // A token cancelled before closes the stream right away.
    final cancelled = CancellationToken()..cancel();
    expect(cancelled.isCancelled(), isTrue);
    expect(await (await client.streamMessage(chatId: chatId, messageId: answerId, cancel: cancelled)).toList(), isEmpty);

    // Cancelling the token closes a live stream.
    final token = CancellationToken();
    var events = StreamIterator(await client.streamMessage(chatId: chatId, messageId: answerId, cancel: token));
    expect(await events.moveNext(), isTrue);
    expect(events.current, isA<MessageEvent_Snapshot>().having((e) => e.message.status, 'status', MessageStatus.generating));
    token.cancel();
    expect(await events.moveNext().timeout(const Duration(seconds: 10)), isFalse);

    // Cancelling the answer ends it with `done`, after which the stream closes.
    events = StreamIterator(await client.streamMessage(chatId: chatId, messageId: answerId, cancel: CancellationToken()));
    expect(await events.moveNext(), isTrue);
    expect(events.current, isA<MessageEvent_Snapshot>());
    await client.cancelMessage(chatId: chatId, messageId: answerId);
    expect(await events.moveNext(), isTrue);
    expect(events.current, isA<MessageEvent_Done>().having((e) => e.message.status, 'status', MessageStatus.cancelled));
    expect(await events.moveNext(), isFalse);
  });
}
