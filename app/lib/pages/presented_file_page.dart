import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/chat/file_content.dart';
import 'package:app/widget/chat/tool_call_info.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The file the model showed with `present_file_to_user`, as it is at the call's commit:
/// Markdown rendered, PDFs in a viewer, other text as it is.
class PresentedFilePage extends StatefulWidget {
  final UuidValue chatId;
  final ToolCallSummaryDto toolCall;
  final String path;

  const PresentedFilePage({super.key, required this.chatId, required this.toolCall, required this.path});

  @override
  State<PresentedFilePage> createState() => _PresentedFilePageState();
}

class _PresentedFilePageState extends State<PresentedFilePage> with Refena {
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
        setState(() => _file = loaded);
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

  @override
  Widget build(BuildContext context) {
    return ToolCallFileScaffold(
      toolCall: widget.toolCall,
      path: widget.path,
      loading: _loading,
      error: _error,
      fill: _file is PdfFile,
      child: switch (_file) {
        final file? => FileContent(file: file, sourceName: widget.toolCall.id.toString()),
        null => null,
      },
    );
  }
}
