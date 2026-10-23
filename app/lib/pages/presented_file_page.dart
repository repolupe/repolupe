import 'dart:convert';
import 'dart:typed_data';

import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/chat/code_block.dart';
import 'package:app/widget/chat/markdown_content.dart';
import 'package:app/widget/chat/tool_call_info.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
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

/// The file as it is shown.
sealed class _LoadedFile {}

class _MarkdownFile extends _LoadedFile {
  final String text;

  _MarkdownFile(this.text);
}

class _TextFile extends _LoadedFile {
  final String text;

  _TextFile(this.text);
}

class _PdfFile extends _LoadedFile {
  final Uint8List content;

  _PdfFile(this.content);
}

/// A file of another type, which the app cannot show.
class _OtherFile extends _LoadedFile {}

class _PresentedFilePageState extends State<PresentedFilePage> with Refena {
  _LoadedFile? _file;
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
      final type = (file.contentType ?? '').split(';').first.trim().toLowerCase();
      final loaded = switch (type) {
        'application/pdf' => _PdfFile(file.content),
        'text/markdown' => _MarkdownFile(utf8.decode(file.content, allowMalformed: true)),
        _ when type.startsWith('text/') => _TextFile(utf8.decode(file.content, allowMalformed: true)),
        _ => _OtherFile(),
      };
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
    final theme = Theme.of(context);
    return ToolCallFileScaffold(
      toolCall: widget.toolCall,
      path: widget.path,
      loading: _loading,
      error: _error,
      fill: _file is _PdfFile,
      child: switch (_file) {
        _MarkdownFile(:final text) => MarkdownContent(content: text),
        _TextFile(:final text) => CodeBlock(text: text),
        _PdfFile(:final content) => PdfViewer.data(content, sourceName: widget.toolCall.id.toString()),
        _OtherFile() => Text(
          context.t.flutter.chat.presentedFilePage.cannotShow,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        null => null,
      },
    );
  }
}
