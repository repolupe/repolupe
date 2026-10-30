import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/client.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/tool_call.dart';
import 'package:app/widget/chat/file_content.dart';
import 'package:app/widget/chat/tool_call_info.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The file the model showed with `present_file_to_user`, as it is at the call's commit:
/// Markdown rendered, PDFs in a viewer, other text as it is. The download button saves it where the user chooses.
class PresentedFilePage extends StatefulWidget {
  final UuidValue chatId;
  final ToolCallSummaryDto toolCall;
  final String path;

  const PresentedFilePage({super.key, required this.chatId, required this.toolCall, required this.path});

  @override
  State<PresentedFilePage> createState() => _PresentedFilePageState();
}

class _PresentedFilePageState extends State<PresentedFilePage> with Refena {
  /// As downloaded, for saving it.
  FileDownload? _download;
  LoadedFile? _file;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    ensureRef((_) => _load());
  }

  Future<void> _load() async {
    try {
      final file = await ref
          .redux(apiProvider)
          .dispatchAsyncTakeResult(ApiGetPresentedFileAction(chatId: widget.chatId, toolCallId: widget.toolCall.id));
      final loaded = LoadedFile.of(file);
      if (mounted) {
        setState(() {
          _download = file;
          _file = loaded;
        });
      }
    } on ClientError catch (e) {
      if (mounted) {
        setState(() => _error = e.userMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save(FileDownload file) async {
    // Without parameters like the charset, which Android's save dialog does not take.
    final type = (file.contentType ?? '').split(';').first.trim();
    try {
      await FilePicker.saveFile(
        fileName: fileName(widget.path),
        bytes: file.content,
        mimeType: type.isEmpty ? 'application/octet-stream' : type,
      );
    } on PlatformException {
      ref.global.dispatch(ShowSnackBarAction(message: t.flutter.chat.fileContent.saveFailed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final download = _download;
    return FileScaffold(
      title: fileName(widget.path),
      header: ToolCallLocation(toolCall: widget.toolCall, path: widget.path),
      loading: _loading,
      error: _error,
      actions: [
        if (download != null)
          IconButton(
            key: const ValueKey('presentedFile.download'),
            icon: const Icon(Icons.download),
            tooltip: context.t.base.common.download,
            onPressed: () => _save(download),
          ),
      ],
      fill: _file is PdfFile,
      child: switch (_file) {
        final file? => FileContent(file: file, sourceName: widget.toolCall.id.toString()),
        null => null,
      },
    );
  }
}
