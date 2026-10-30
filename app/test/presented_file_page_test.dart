import 'dart:convert';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/presented_file_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/client.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/api.dart';
import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const _chatId = '0199a8d4-6d5e-7c3a-9b1f-000000000001';
const _toolCallId = '0199a8d4-6d5e-7c3a-9b1f-000000000007';
const _repositoryId = '0199a8d4-6d5e-7c3a-9b1f-000000000006';

/// The `present_file_to_user` call whose file the page shows.
final _toolCall = ToolCallSummaryDto(
  id: UuidValue.fromString(_toolCallId),
  name: 'present_file_to_user',
  input: jsonEncode({'repository': 'docs', 'path': 'guide/README.md'}),
  repositoryId: UuidValue.fromString(_repositoryId),
  commitSha: 'abc123',
  status: ToolCallStatus.completed,
  createdAt: DateTime.utc(2026, 10, 21, 12),
);

/// Records what it is asked to save, failing if [error] is set.
class _FakeFilePicker extends FilePickerPlatform {
  final PlatformException? error;
  final saved = <(String, Uint8List, String)>[];

  _FakeFilePicker({this.error});

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    if (error case final error?) {
      throw error;
    }
    saved.add((fileName, bytes, mimeType));
    return Uri.file('/saved/$fileName');
  }
}

/// Opens the page of the `present_file_to_user` call, which loads `# Guide` as Markdown.
Future<void> _openPage(WidgetTester tester) async {
  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: _userId),
      api: (mock) {
        mock.on<ApiGetPresentedFileAction>(
          (state, _) => (
            state,
            FileDownload(content: Uint8List.fromList(utf8.encode('# Guide')), contentType: 'text/markdown; charset=utf-8'),
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
          home: PresentedFilePage(chatId: UuidValue.fromString(_chatId), toolCall: _toolCall, path: 'guide/README.md'),
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

  testWidgets('the file is saved under its name with its content type', (tester) async {
    final picker = _FakeFilePicker();
    FilePickerPlatform.instance = picker;

    await _openPage(tester);
    expect(find.text('Guide', findRichText: true), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('presentedFile.download')));
    await tester.pump();

    expect(picker.saved, hasLength(1));
    final (name, bytes, mimeType) = picker.saved.single;
    expect(name, 'README.md');
    expect(utf8.decode(bytes), '# Guide');
    expect(mimeType, 'text/markdown');
  });

  testWidgets('a failed save shows a snack bar', (tester) async {
    FilePickerPlatform.instance = _FakeFilePicker(error: PlatformException(code: 'error'));

    await _openPage(tester);
    await tester.tap(find.byKey(const ValueKey('presentedFile.download')));
    await tester.pump();

    expect(find.text('The file could not be saved.'), findsOneWidget);
  });
}
