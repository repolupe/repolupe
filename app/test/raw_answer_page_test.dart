import 'dart:convert';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/raw_answer_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/mirror.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
final _chatId = UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000001');
final _messageId = UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000002');

/// A question answered after a `read_file` call that worked and a `grep` call whose arguments were no JSON object and
/// that failed.
const _raw = RawAnswerDto(
  system: 'You answer questions.',
  tools: [RawToolDto(name: 'read_file', description: 'Reads a file.', inputSchema: '{"type":"object"}')],
  messages: [
    RawMessageDto(
      role: MessageRole.user,
      content: [RawBlockDto.text(text: 'What is in the README?')],
    ),
    RawMessageDto(
      role: MessageRole.assistant,
      content: [
        RawBlockDto.reasoning(text: '', redacted: true),
        RawBlockDto.toolUse(id: 'call_1', name: 'read_file', input: '{"path":"README.md"}'),
        RawBlockDto.toolUse(id: 'call_2', name: 'grep', input: '"not an object"'),
      ],
    ),
    RawMessageDto(
      role: MessageRole.user,
      content: [
        RawBlockDto.toolResult(toolUseId: 'call_1', content: '# Guide', isError: false),
        RawBlockDto.toolResult(toolUseId: 'call_2', content: 'Invalid arguments', isError: true),
      ],
    ),
    RawMessageDto(
      role: MessageRole.assistant,
      content: [
        RawBlockDto.text(text: 'A guide.'),
        RawBlockDto.unknown(),
      ],
    ),
  ],
);

/// Opens the page of an answer whose raw answer [load] returns, on a screen that fits all of it.
Future<void> _openPage(WidgetTester tester, {RawAnswerDto Function()? load}) async {
  // Tall enough for the list to build all of it.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: _userId),
      api: (mock) {
        mock.on<ApiGetRawAnswerAction>((state, action) {
          expect((action.chatId, action.messageId), (_chatId, _messageId));
          return (state, (load ?? () => _raw)());
        });
      },
    ),
  ))!;
  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          scaffoldMessengerKey: container.read(snackBarProvider).key,
          home: RawAnswerPage(chatId: _chatId, messageId: _messageId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the messages are shown block by block, the system prompt and the tools once asked for', (tester) async {
    await _openPage(tester);
    final texts = t.base.chat.rawAnswerDialog;

    expect(find.text(texts.systemPrompt), findsOneWidget);
    expect(find.text('You answer questions.'), findsNothing);
    expect(find.text('${texts.tools} (1)'), findsNothing);

    expect(find.text('What is in the README?'), findsOneWidget);
    expect(find.text(texts.user), findsOneWidget);
    expect(find.text(texts.assistant), findsNWidgets(2));
    expect(find.text(texts.reasoningWithheld), findsOneWidget);
    // The labels have their icon and chip in the text.
    expect(find.textContaining('${texts.toolUse}: call_1', findRichText: true), findsOneWidget);
    // Indented, but arguments that are a string as the model sent them.
    expect(find.text('{\n  "path": "README.md"\n}'), findsOneWidget);
    expect(find.text('not an object'), findsOneWidget);
    // The message of the results is headed as such, so each result only names its call.
    expect(find.text(texts.toolResult), findsOneWidget);
    expect(find.text('read_file (call_1)', findRichText: true), findsOneWidget);
    expect(find.textContaining('grep (call_2)', findRichText: true), findsOneWidget);
    expect(find.text(texts.error), findsOneWidget);
    expect(find.text('# Guide'), findsOneWidget);
    expect(find.text('A guide.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rawAnswer.toggleSystem')));
    await tester.pump();
    expect(find.text('You answer questions.'), findsOneWidget);
    expect(find.text('${texts.tools} (1)'), findsOneWidget);
    expect(find.text('Reads a file.'), findsOneWidget);
    expect(find.text('{\n  "type": "object"\n}'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rawAnswer.toggleSystem')));
    await tester.pump();
    expect(find.text('You answer questions.'), findsNothing);
    expect(find.text('Reads a file.'), findsNothing);
  });

  testWidgets('it is copied as the JSON of the API', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _openPage(tester);
    await tester.tap(find.byKey(const ValueKey('rawAnswer.copy')));
    await tester.pump();

    expect(find.text(t.base.chat.rawAnswerDialog.copied), findsOneWidget);
    expect(copied, contains('\n  "system": "You answer questions.",\n'));
    final json = jsonDecode(copied!) as Map<String, dynamic>;
    expect(json['tools'], [
      {
        'name': 'read_file',
        'description': 'Reads a file.',
        'input_schema': {'type': 'object'},
      },
    ]);
    final messages = json['messages'] as List<dynamic>;
    expect(messages[0], {
      'role': 'USER',
      'content': [
        {'type': 'TEXT', 'text': 'What is in the README?'},
      ],
    });
    expect(messages[1], {
      'role': 'ASSISTANT',
      'content': [
        {'type': 'REASONING', 'text': '', 'redacted': true},
        {
          'type': 'TOOL_USE',
          'id': 'call_1',
          'name': 'read_file',
          'input': {'path': 'README.md'},
        },
        {'type': 'TOOL_USE', 'id': 'call_2', 'name': 'grep', 'input': 'not an object'},
      ],
    });
    expect((messages[2] as Map<String, dynamic>)['content'], [
      {'type': 'TOOL_RESULT', 'tool_use_id': 'call_1', 'content': '# Guide', 'is_error': false},
      {'type': 'TOOL_RESULT', 'tool_use_id': 'call_2', 'content': 'Invalid arguments', 'is_error': true},
    ]);
  });

  testWidgets('an answer nothing is stored for says so, and cannot be copied', (tester) async {
    await _openPage(tester, load: () => throw apiError(ErrorCode.notFound, status: 404));

    expect(find.text(t.base.chat.rawAnswerDialog.notAvailable), findsOneWidget);
    expect(find.byKey(const ValueKey('rawAnswer.copy')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a raw answer that fails to load shows why', (tester) async {
    await _openPage(tester, load: () => throw apiError(ErrorCode.internalError, status: 500));

    final texts = t.base;
    expect(find.text(texts.chat.rawAnswerDialog.loadFailed(error: texts.errors.internalError)), findsOneWidget);
    expect(find.text(texts.chat.rawAnswerDialog.notAvailable), findsNothing);
  });
}
