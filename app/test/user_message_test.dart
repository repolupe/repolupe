import 'dart:convert';
import 'dart:typed_data';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/attachment_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/client.dart';
import 'package:app/src/rust/third_party/repolupe/dto/attachment.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/widget/chat/file_content.dart';
import 'package:app/widget/chat/user_message.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/file_picker.dart';
import 'support/rust.dart';

const _messageId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';

AttachmentDto _attachment(String fileName, String contentType, {int size = 7}) => AttachmentDto(
  id: UuidValue.fromString('0199a8d4-6d5e-7c3a-9b1f-000000000008'),
  number: 1,
  fileName: fileName,
  contentType: contentType,
  size: size,
  createdAt: DateTime.utc(2026, 11, 13, 12),
);

/// Shows a message with [attachment], whose file is `# Notes`, or fails to load with [error].
Future<void> _pumpMessage(WidgetTester tester, AttachmentDto attachment, {ErrorCode? error}) async {
  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: 'user'),
      api: (mock) {
        mock.on<ApiDownloadAttachmentAction>((state, _) {
          if (error != null) {
            throw apiError(error, status: 404, message: 'Not found');
          }
          return (
            state,
            FileDownload(
              content: Uint8List.fromList(utf8.encode('# Notes')),
              contentType: attachment.contentType,
              fileName: attachment.fileName,
            ),
          );
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
          home: Scaffold(
            body: UserMessage(
              message: MessageDto(
                id: UuidValue.fromString(_messageId),
                role: MessageRole.user,
                content: 'See the file',
                status: MessageStatus.completed,
                toolCalls: const [],
                createdAt: DateTime.utc(2026, 11, 13, 12),
                attachment: attachment,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _button = find.byKey(const ValueKey('chat.message.$_messageId.attachment'));

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  test('the files the app shows are those the web shows', () {
    expect(_attachment('invoice.pdf', 'application/pdf').canShow, isTrue);
    expect(_attachment('photo.jpg', 'image/jpeg').canShow, isTrue);
    expect(_attachment('scan.tiff', 'image/tiff').canShow, isFalse);
    expect(_attachment('data.csv', 'text/csv').canShow, isTrue);
    expect(_attachment('server.log', 'text/plain', size: 2 * 1024 * 1024).canShow, isFalse);
    expect(_attachment('archive.zip', 'application/zip').canShow, isFalse);
    expect(FileKind.of(contentType: 'text/markdown; charset=utf-8'), FileKind.markdown);
    expect(FileKind.of(contentType: 'application/octet-stream', fileName: 'README.MD'), FileKind.markdown);
    expect(FileKind.of(contentType: 'application/octet-stream', fileName: 'report.docx'), isNull);
  });

  testWidgets('a Markdown attachment without a text type is shown rendered', (tester) async {
    final picker = FakeFilePicker();
    FilePickerPlatform.instance = picker;

    await _pumpMessage(tester, _attachment('Notes.md', 'application/octet-stream'));
    await tester.tap(_button);
    await tester.pumpAndSettle();

    expect(find.byType(AttachmentPage), findsOneWidget);
    expect(find.text('Notes', findRichText: true), findsOneWidget);
    expect(picker.saved, isEmpty);
  });

  testWidgets('an attachment the app cannot show is saved right away', (tester) async {
    final picker = FakeFilePicker();
    FilePickerPlatform.instance = picker;

    await _pumpMessage(tester, _attachment('archive.zip', 'application/zip'));
    await tester.tap(_button);
    await tester.pumpAndSettle();

    expect(find.byType(AttachmentPage), findsNothing);
    final (name, bytes, mimeType) = picker.saved.single;
    expect(name, 'archive.zip');
    expect(utf8.decode(bytes), '# Notes');
    expect(mimeType, 'application/zip');
    // ready for another tap
    expect(tester.widget<ButtonStyleButton>(_button).enabled, isTrue);
  });

  testWidgets('an attachment that cannot be loaded to save it shows a snack bar', (tester) async {
    final picker = FakeFilePicker();
    FilePickerPlatform.instance = picker;

    await _pumpMessage(tester, _attachment('archive.zip', 'application/zip'), error: ErrorCode.notFound);
    await tester.tap(_button);
    await tester.pumpAndSettle();

    expect(picker.saved, isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(_button).enabled, isTrue);
  });
}
