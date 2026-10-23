import 'package:app/pages/chat_page.dart';
import 'package:app/service/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import '../util/sample_data.dart';
import '../util/screenshot_scaffold.dart';

/// Screenshot tests for a chat, in light and dark mode.
///
/// Run `flutter test test/screenshot --update-goldens`
/// to (re)generate the golden images, or `flutter test test/screenshot` to compare against them.
void main() {
  initScreenshotTest();

  screenshotGroup(
    description: 'Chat (light)',
    title: 'Chat with your\nprivate knowledge',
    routes: {
      ...baseRoutes(),
      '/api/v1/chats/$taxChatId': chatDetail(
        id: taxChatId,
        title: 'Tax ID',
        repositoryId: documentsId,
        exchanges: [
          (
            question: 'When does my car insurance renew?',
            toolCalls: [
              ('read_file', {'repository': 'documents', 'path': 'Insurance/Car-Policy.pdf'}),
              ('present_file_to_user', {'repository': 'documents', 'path': 'Insurance/Car-Policy.pdf'}),
            ],
            answer: 'On **March 1**. You can cancel it until **January 31**, as your policy says.',
          ),
          (
            question: 'What is my tax ID?',
            toolCalls: [
              ('grep', {'repository': 'documents', 'pattern': 'tax ID', 'path': 'Taxes'}),
              ('present_file_to_user', {'repository': 'documents', 'path': 'Taxes/Assessment-2024.pdf'}),
            ],
            answer:
                'Your tax ID is **83 715 692 048**. It is listed in your income tax assessments:\n\n'
                '- `Taxes/Assessment-2023.pdf`\n'
                '- `Taxes/Assessment-2024.pdf`',
          ),
        ],
      ),
    },
    home: const ChatPage(),
    prepare: (container) => _open(container, taxChatId),
    ready: find.textContaining('83 715 692 048', findRichText: true),
    goldenFileName: '1_chat_light',
  );

  screenshotGroup(
    description: 'Chat (dark)',
    title: 'Ask questions.\nOr add what you know.',
    brightness: Brightness.dark,
    routes: {
      ...baseRoutes(),
      '/api/v1/chats/$passportChatId': chatDetail(
        id: passportChatId,
        title: 'Passport renewal',
        repositoryId: notesId,
        exchanges: [
          (
            question: 'When does my passport expire?',
            toolCalls: [
              ('grep', {'repository': 'notes', 'pattern': 'passport'}),
            ],
            answer: 'On **November 14, 2026**, in about three weeks (`Personal/IDs.md`).',
          ),
          (
            question: 'I just renewed it. The new one is valid until October 2036.',
            toolCalls: [
              ('read_file', {'repository': 'notes', 'path': 'Personal/IDs.md'}),
              ('change_file', {'repository': 'notes', 'path': 'Personal/IDs.md'}),
              ('read_file', {'repository': 'notes', 'path': 'Reminders.md'}),
              ('change_file', {'repository': 'notes', 'path': 'Reminders.md'}),
            ],
            answer:
                'Great! I updated your notes:\n\n'
                '- `Personal/IDs.md`: your passport is now valid until **October 20, 2036**.\n'
                '- `Reminders.md`: I removed the reminder to renew it.\n\n'
                'Review the changes before they are applied.',
          ),
        ],
      ),
    },
    home: const ChatPage(),
    prepare: (container) => _open(container, passportChatId),
    ready: find.textContaining('2036', findRichText: true),
    goldenFileName: '2_chat_dark',
  );
}

/// Opens the chat [id] once the new chat of the page loaded the models and repositories, which it keeps.
Future<void> _open(RefenaContainer container, String id) async {
  await container.redux(chatProvider).dispatchAsync(NewChatAction());
  await container.redux(chatProvider).dispatchAsync(OpenChatAction(UuidValue.fromString(id)));
}
