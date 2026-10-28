import 'package:app/gen/strings.g.dart';
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
  initScreenshotTest(locale: AppLocale.de);

  screenshotGroup(
    description: 'Chat (light)',
    title: 'Chatte mit deinem\nprivaten Wissen',
    api: sampleApi(
      germanTexts,
      chatDetails: [
        chatDetail(
          id: taxChatId,
          title: germanTexts.taxChat,
          repositoryId: documentsId,
          exchanges: [
            (
              question: 'Wann verlängert sich meine Kfz-Versicherung?',
              toolCalls: [
                ('read_file', {'repository': germanTexts.documents, 'path': 'Versicherungen/Kfz-Police.pdf'}),
                ('present_file_to_user', {'repository': germanTexts.documents, 'path': 'Versicherungen/Kfz-Police.pdf'}),
              ],
              answer: 'Am **1. März**. Laut deiner Police kannst du sie bis zum **31. Januar** kündigen.',
            ),
            (
              question: 'Wie lautet meine Steuer-ID?',
              toolCalls: [
                ('grep', {'repository': germanTexts.documents, 'pattern': 'Steuer-ID', 'path': 'Steuern'}),
                ('present_file_to_user', {'repository': germanTexts.documents, 'path': 'Steuern/Bescheid-2024.pdf'}),
              ],
              answer:
                  'Deine Steuer-ID ist **83 715 692 048**. Sie steht in deinen Einkommensteuerbescheiden:\n\n'
                  '- `Steuern/Bescheid-2023.pdf`\n'
                  '- `Steuern/Bescheid-2024.pdf`',
            ),
          ],
        ),
      ],
    ),
    home: const ChatPage(),
    prepare: (container) => _open(container, taxChatId),
    ready: find.textContaining('83 715 692 048', findRichText: true),
    goldenFileName: '1_chat_light',
  );

  screenshotGroup(
    description: 'Chat (dark)',
    title: 'Fragen stellen.\nWissen ergänzen.',
    brightness: Brightness.dark,
    api: sampleApi(
      germanTexts,
      chatDetails: [
        chatDetail(
          id: passportChatId,
          title: germanTexts.passportChat,
          repositoryId: notesId,
          exchanges: [
            (
              question: 'Wann läuft mein Reisepass ab?',
              toolCalls: [
                ('grep', {'repository': germanTexts.notes, 'pattern': 'Reisepass'}),
              ],
              answer: 'Am **14. November 2026**, also in etwa drei Wochen (`Persönlich/Ausweise.md`).',
            ),
            (
              question: 'Ich habe ihn gerade verlängert. Der neue ist bis Oktober 2036 gültig.',
              toolCalls: [
                ('read_file', {'repository': germanTexts.notes, 'path': 'Persönlich/Ausweise.md'}),
                ('change_file', {'repository': germanTexts.notes, 'path': 'Persönlich/Ausweise.md'}),
                ('read_file', {'repository': germanTexts.notes, 'path': 'Erinnerungen.md'}),
                ('change_file', {'repository': germanTexts.notes, 'path': 'Erinnerungen.md'}),
              ],
              answer:
                  'Super! Ich habe deine Notizen aktualisiert:\n\n'
                  '- `Persönlich/Ausweise.md`: Dein Reisepass ist jetzt bis zum **20. Oktober 2036** gültig.\n'
                  '- `Erinnerungen.md`: Ich habe die Erinnerung entfernt, ihn zu verlängern.\n\n'
                  'Prüfe die Änderungen, bevor sie übernommen werden.',
            ),
          ],
        ),
      ],
    ),
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
