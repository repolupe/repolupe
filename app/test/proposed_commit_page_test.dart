import 'dart:convert';
import 'dart:io';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/pages/proposed_commit_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _chatId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';
const _toolCallId = '0199a8d4-6d5e-7c3a-9b1f-000000000007';
const _repositoryId = '0199a8d4-6d5e-7c3a-9b1f-000000000006';

const _diff = FileDiffDto(
  kind: DiffFileKind.modified,
  hunks: [
    DiffHunkDto(
      skipped: false,
      lines: [
        DiffLineDto(
          kind: DiffLineKind.removed,
          parts: [DiffPartDto(text: 'Helo', changed: false)],
        ),
        DiffLineDto(
          kind: DiffLineKind.added,
          parts: [DiffPartDto(text: 'Hello', changed: false)],
        ),
      ],
    ),
  ],
);

/// The change of `README.md` in [status], committed to `main` if it is [ProposedCommitStatus.committed].
ProposedCommitDto _change(ProposedCommitStatus status, {String? error}) {
  final committed = status == ProposedCommitStatus.committed;
  return ProposedCommitDto(
    path: 'README.md',
    proposedCommit: '1234567',
    status: status,
    pushedCommit: committed ? '1234567' : null,
    pushedBranch: committed ? 'main' : null,
    error: error,
    committedAt: committed ? DateTime.utc(2026, 10, 21, 12, 5) : null,
    canCommit: true,
  );
}

/// The `change_file` call whose change the page shows.
final _toolCall = ToolCallSummaryDto(
  id: UuidValue.fromString(_toolCallId),
  name: 'change_file',
  input: jsonEncode({'repository': 'docs', 'path': 'README.md', 'message': 'Fix typo'}),
  repositoryId: UuidValue.fromString(_repositoryId),
  commitSha: 'abc123',
  status: ToolCallStatus.completed,
  createdAt: DateTime.utc(2026, 10, 21, 12),
);

/// Opens the page of the `change_file` call on the chat page, the API actions answered by [api].
Future<RefenaContainer> _openPage(WidgetTester tester, void Function(ApiMocks mock) api) async {
  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: _userId),
      api: api,
    ),
  ))!;
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

  // ignore: discarded_futures
  container
      .read(navigationProvider)
      .key
      .currentState!
      .push(
        MaterialPageRoute<void>(
          builder: (_) => ProposedCommitPage(chatId: UuidValue.fromString(_chatId), toolCall: _toolCall, path: 'README.md'),
        ),
      );
  return container;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('a proposed change is applied, trying again after a conflict, and the page closes', (tester) async {
    final commits = <ApiCommitProposedCommitAction>[];
    await _openPage(
      tester,
      (mock) {
        mock.on<ApiGetProposedCommitDiffAction>((state, _) => (state, _diff));
        mock.on<ApiGetProposedCommitAction>((state, _) => (state, _change(ProposedCommitStatus.proposed)));
        mock.on<ApiCommitProposedCommitAction>((state, action) {
          commits.add(action);
          return (
            state,
            commits.length == 1
                ? _change(ProposedCommitStatus.conflict, error: 'README.md changed on the branch.')
                : _change(ProposedCommitStatus.committed),
          );
        });
      },
    );
    // The page slides in.
    await tester.pumpAndSettle();
    expect(find.text('Apply Change'), findsOneWidget);
    expect(find.text('Fix typo'), findsOneWidget);
    expect(find.text('Hello', findRichText: true), findsOneWidget);
    expect(find.text('docs › README.md'), findsOneWidget);

    await tester.tap(find.text('Apply Change'));
    await tester.pump();
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('README.md changed on the branch.'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pump();
    expect(find.text('Applied the change to README.md'), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.byType(ProposedCommitPage), findsNothing);
    expect(find.text('Chat'), findsOneWidget);
    final change = (UuidValue.fromString(_chatId), UuidValue.fromString(_toolCallId));
    expect([for (final commit in commits) (commit.chatId, commit.toolCallId)], [change, change]);
  });

  // The only request that goes to a server: the content type is set by the Rust client.
  test('the commit is sent as JSON, which the CSRF protection requires', () async {
    final contentTypes = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final response = request.response;
      if (request.method == 'POST' && request.uri.path == '/api/v1/chats/$_chatId/tool-calls/$_toolCallId/commit') {
        contentTypes.add(request.headers.contentType?.mimeType ?? '');
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'path': 'README.md',
            'moves': null,
            'proposed_commit': '1234567',
            'status': 'COMMITTED',
            'pushed_commit': '1234567',
            'pushed_branch': 'main',
            'error': null,
            'committed_at': '2026-10-21T12:05:00+00:00',
            'can_commit': true,
          }),
        );
      } else {
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
              user: AccountUser(id: _userId, userName: 'alice'),
            ),
          ),
        );
    final change = await container
        .redux(apiProvider)
        .dispatchAsyncTakeResult(
          ApiCommitProposedCommitAction(chatId: UuidValue.fromString(_chatId), toolCallId: UuidValue.fromString(_toolCallId)),
        );
    expect(change.status, ProposedCommitStatus.committed);
    expect(contentTypes, ['application/json']);
  });

  testWidgets('enabling auto-commit turns it on and applies the change', (tester) async {
    final requests = <String>[];
    var autoCommit = false;
    final container = await _openPage(
      tester,
      (mock) {
        mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _userId, autoCommit: autoCommit)));
        mock.on<ApiSetAutoCommitAction>((state, action) {
          requests.add('auto-commit ${action.autoCommit}');
          autoCommit = action.autoCommit;
          return state;
        });
        mock.on<ApiGetProposedCommitDiffAction>((state, _) => (state, _diff));
        mock.on<ApiGetProposedCommitAction>((state, _) => (state, _change(ProposedCommitStatus.proposed)));
        mock.on<ApiCommitProposedCommitAction>((state, action) {
          requests.add('commit');
          return (state, _change(ProposedCommitStatus.committed));
        });
      },
    );
    await container.redux(meProvider).dispatchAsync(RefreshMeAction());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enable auto-commit'));
    await tester.pumpAndSettle();
    expect(find.text('Enable auto-commit?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('proposedCommit.autoCommit.confirm')));
    await tester.pump();
    expect(find.text('Applied the change to README.md'), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.byType(ProposedCommitPage), findsNothing);
    expect(requests, ['auto-commit true', 'commit']);
    expect(container.read(meProvider)?.autoCommit, isTrue);
  });
}
