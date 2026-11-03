import 'dart:convert';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/attachment_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/client.dart';
import 'package:app/src/rust/third_party/repolupe/dto/attachment.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/file_picker.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _attachmentId = '0199a8d4-6d5e-7c3a-9b1f-000000000008';

final _attachment = AttachmentDto(
  id: UuidValue.fromString(_attachmentId),
  number: 1,
  fileName: 'Notes.md',
  contentType: 'text/markdown',
  size: 7,
  createdAt: DateTime.utc(2026, 10, 21, 12),
);

/// Opens the page of the attachment, which loads `# Notes` as Markdown.
Future<void> _openPage(WidgetTester tester) async {
  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: _userId),
      api: (mock) {
        mock.on<ApiDownloadAttachmentAction>(
          (state, _) => (
            state,
            FileDownload(
              content: Uint8List.fromList(utf8.encode('# Notes')),
              contentType: 'text/markdown; charset=utf-8',
              fileName: 'Notes.md',
            ),
          ),
        );
      },
    ),
  ))!;
  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          scaffoldMessengerKey: container.read(snackBarProvider).key,
          home: AttachmentPage(attachment: _attachment),
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

  testWidgets('the attachment is saved under its name with its content type', (tester) async {
    final picker = FakeFilePicker();
    FilePickerPlatform.instance = picker;

    await _openPage(tester);
    expect(find.text('Notes', findRichText: true), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('attachment.download')));
    await tester.pump();

    expect(picker.saved, hasLength(1));
    final (name, bytes, mimeType) = picker.saved.single;
    expect(name, 'Notes.md');
    expect(utf8.decode(bytes), '# Notes');
    expect(mimeType, 'text/markdown');
  });

  testWidgets('a failed save shows a snack bar', (tester) async {
    FilePickerPlatform.instance = FakeFilePicker(error: PlatformException(code: 'error'));

    await _openPage(tester);
    await tester.tap(find.byKey(const ValueKey('attachment.download')));
    await tester.pump();

    expect(find.text('The file could not be saved.'), findsOneWidget);
  });
}
