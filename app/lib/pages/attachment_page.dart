import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/client.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/attachment.dart';
import 'package:app/widget/chat/file_content.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// A file the user attached to a message: Markdown rendered, PDFs in a viewer, images zoomable, other text as it is.
/// The download button saves it where the user chooses.
class AttachmentPage extends StatefulWidget {
  final AttachmentDto attachment;

  const AttachmentPage({super.key, required this.attachment});

  @override
  State<AttachmentPage> createState() => _AttachmentPageState();
}

class _AttachmentPageState extends State<AttachmentPage> with Refena {
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
      final file = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiDownloadAttachmentAction(attachmentId: widget.attachment.id));
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

  @override
  Widget build(BuildContext context) {
    final download = _download;
    return FileScaffold(
      title: widget.attachment.fileName,
      loading: _loading,
      error: _error,
      actions: [
        if (download != null)
          DownloadButton(
            key: const ValueKey('attachment.download'),
            file: download,
            fileName: widget.attachment.fileName,
          ),
      ],
      fill: _file?.fillsPage ?? false,
      child: switch (_file) {
        final file? => FileContent(file: file, sourceName: widget.attachment.id.toString()),
        null => null,
      },
    );
  }
}
