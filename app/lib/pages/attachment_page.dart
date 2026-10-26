import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/attachment.dart';
import 'package:app/widget/chat/file_content.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// A file the user attached to a message: Markdown rendered, PDFs in a viewer, other text as it is.
class AttachmentPage extends StatefulWidget {
  final AttachmentDto attachment;

  const AttachmentPage({super.key, required this.attachment});

  @override
  State<AttachmentPage> createState() => _AttachmentPageState();
}

class _AttachmentPageState extends State<AttachmentPage> with Refena {
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
      final file = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiDownloadAttachmentAction(attachmentId: widget.attachment.id));
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
    return FileScaffold(
      title: widget.attachment.fileName,
      loading: _loading,
      error: _error,
      fill: _file is PdfFile,
      child: switch (_file) {
        final file? => FileContent(file: file, sourceName: widget.attachment.id.toString()),
        null => null,
      },
    );
  }
}
