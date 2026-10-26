import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/older_chats_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/fake_user.dart';
import 'support/rust.dart';

/// The id of the chat [index], from the newest.
String _chatId(int index) => '0199a8d4-6d5e-7c3a-9b1f-${index.toString().padLeft(12, '0')}';

Map<String, dynamic> _chat(int index) => {
  'id': _chatId(index),
  'title': 'Chat $index',
  'all_repositories': true,
  'repository_ids': <Object>[],
  'model_id': null,
  'temporary': false,
  'created_at': '2026-10-21T12:00:00+00:00',
  'updated_at': '2026-10-21T12:00:00+00:00',
};

/// Pumps until [finder] finds something, letting the requests to the server run meanwhile.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the older chats start after the cursor, load more at the end, and a tapped one is opened', (tester) async {
    final requests = <String>[];
    final server = (await tester.runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0)))!;
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests.add(request.uri.toString());
      final response = request.response;
      response.headers.contentType = ContentType.json;
      switch ((request.uri.path, request.uri.queryParameters['cursor'])) {
        // The drawer showed chats 0 to 9.
        case ('/api/v1/chats', 'drawer'):
          response.write(
            jsonEncode({
              'items': [for (var i = 10; i < 60; i++) _chat(i)],
              'next_cursor': 'second',
            }),
          );
        case ('/api/v1/chats', 'second'):
          response.write(
            jsonEncode({
              'items': [for (var i = 60; i < 62; i++) _chat(i)],
              'next_cursor': null,
            }),
          );
        case (final path, _) when path == '/api/v1/chats/${_chatId(61)}':
          response.write(jsonEncode({..._chat(61), 'messages': <Object>[]}));
        default:
          response.statusCode = 404;
          response.write(jsonEncode(fakeError('NOT_FOUND', 'Not found')));
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
    // Not settled, the progress indicator spins until the chats are loaded.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await _pumpUntil(tester, find.text('Chat 10'));
    expect(requests, ['/api/v1/chats?limit=50&cursor=drawer']);
    expect(find.text('Older Chats'), findsOneWidget);

    // The end of the list loads the rest, then there is nothing more to load.
    await tester.scrollUntilVisible(find.text('Chat 59'), 500, scrollable: find.byType(Scrollable));
    await tester.drag(find.byKey(const ValueKey('olderChats.list')), const Offset(0, -500));
    await _pumpUntil(tester, find.text('Chat 61'));
    await tester.pumpAndSettle();
    expect(requests, ['/api/v1/chats?limit=50&cursor=drawer', '/api/v1/chats?limit=50&cursor=second']);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Tapping a chat goes back and opens it.
    await tester.ensureVisible(find.text('Chat 61'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat 61'));
    await tester.pumpAndSettle();
    expect(find.text('Chat page'), findsOneWidget);
    for (var i = 0; i < 100 && container.read(chatProvider).chat == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    expect(container.read(chatProvider).chat?.title, 'Chat 61');
  });
}
