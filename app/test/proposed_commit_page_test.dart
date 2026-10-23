import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/proposed_commit_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/rust.dart';

const _chatId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';
const _toolCallId = '0199a8d4-6d5e-7c3a-9b1f-000000000007';
const _repositoryId = '0199a8d4-6d5e-7c3a-9b1f-000000000006';

const _diff = {
  'kind': 'MODIFIED',
  'hunks': [
    {
      'skipped': false,
      'lines': [
        {
          'kind': 'REMOVED',
          'parts': [
            {'text': 'Helo', 'changed': false},
          ],
        },
        {
          'kind': 'ADDED',
          'parts': [
            {'text': 'Hello', 'changed': false},
          ],
        },
      ],
    },
  ],
  'moves': null,
};

Map<String, dynamic> _change(String status, {String? error}) => {
  'path': 'README.md',
  'moves': null,
  'proposed_commit': '1234567',
  'status': status,
  'pushed_commit': status == 'COMMITTED' ? '1234567' : null,
  'pushed_branch': status == 'COMMITTED' ? 'main' : null,
  'error': error,
  'committed_at': status == 'COMMITTED' ? '2026-10-21T12:05:00+00:00' : null,
  'can_commit': true,
};

/// Pumps until [finder] finds something, letting the requests to the server run meanwhile.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('a proposed change is applied, trying again after a conflict, and the page closes', (tester) async {
    final commits = <String>[];
    final server = (await tester.runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0)))!;
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final response = request.response;
      switch ((request.method, request.uri.path)) {
        case ('GET', '/api/v1/chats/$_chatId/tool-calls/$_toolCallId/diff'):
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(_diff));
        case ('GET', '/api/v1/chats/$_chatId/tool-calls/$_toolCallId/proposed-commit'):
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(_change('PROPOSED')));
        case ('POST', '/api/v1/chats/$_chatId/tool-calls/$_toolCallId/commit'):
          commits.add(request.headers.contentType?.mimeType ?? '');
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode(commits.length == 1 ? _change('CONFLICT', error: 'README.md changed on the branch.') : _change('COMMITTED')),
          );
        default:
          response.statusCode = 404;
      }
      await response.close();
    });

    final container = RefenaContainer();
    container
        .redux(apiProvider)
        .dispatch(
          ApiSetAccountAction(
            Account(
              apiUrl: 'http://127.0.0.1:${server.port}',
              token: 'session-token',
              user: AccountUser(id: '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12', userName: 'alice'),
            ),
          ),
        );
    await tester.pumpWidget(
      RefenaScope.withContainer(
        container: container,
        child: TranslationProvider(
          child: MaterialApp(
            navigatorKey: container.read(navigationProvider).key,
            scaffoldMessengerKey: container.read(snackBarProvider).key,
            home: const Scaffold(body: Text('Chat')),
          ),
        ),
      ),
    );

    final toolCall = ToolCallSummaryDto(
      id: UuidValue.fromString(_toolCallId),
      name: 'change_file',
      input: jsonEncode({'repository': 'docs', 'path': 'README.md', 'message': 'Fix typo'}),
      repositoryId: UuidValue.fromString(_repositoryId),
      commitSha: 'abc123',
      status: ToolCallStatus.completed,
      createdAt: DateTime.utc(2026, 10, 21, 12),
    );
    // ignore: discarded_futures
    container
        .read(navigationProvider)
        .key
        .currentState!
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ProposedCommitPage(chatId: UuidValue.fromString(_chatId), toolCall: toolCall, path: 'README.md'),
          ),
        );
    await _pumpUntil(tester, find.text('Apply Change'));
    // The page slides in.
    await tester.pumpAndSettle();
    expect(find.text('Fix typo'), findsOneWidget);
    expect(find.text('Hello', findRichText: true), findsOneWidget);
    expect(find.text('docs › README.md'), findsOneWidget);

    await tester.tap(find.text('Apply Change'));
    await _pumpUntil(tester, find.text('Try Again'));
    expect(find.text('README.md changed on the branch.'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await _pumpUntil(tester, find.text('Applied the change to README.md'));
    await tester.pumpAndSettle();
    expect(find.byType(ProposedCommitPage), findsNothing);
    expect(find.text('Chat'), findsOneWidget);
    // JSON, which the CSRF protection requires.
    expect(commits, ['application/json', 'application/json']);
  });
}
