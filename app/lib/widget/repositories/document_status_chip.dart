import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/extraction.dart';
import 'package:app/widget/status_chip.dart';
import 'package:flutter/material.dart';

/// Which documents a filter shows: a document is pending while it is converted with the current settings, else
/// it is failed or converted, like the web's categories.
DocumentFilter documentCategory(RepositoryDocumentDto document) {
  if (document.conversion != null) {
    return DocumentFilter.pending;
  }
  return document.extraction?.status == DocumentExtractionStatus.failed ? DocumentFilter.failed : DocumentFilter.converted;
}

/// The conversion status of a document as a small colored chip.
class DocumentStatusChip extends StatelessWidget {
  final RepositoryDocumentDto document;

  const DocumentStatusChip({super.key, required this.document});

  /// The label, color and icon of a document's status, like the web shows them.
  static (String, Color, IconData) info(BuildContext context, RepositoryDocumentDto document) {
    final status = context.t.base.status;
    switch (document.conversion?.status) {
      case DocumentConversionStatus.waiting:
        return (status.waiting, Colors.grey, Icons.schedule);
      case DocumentConversionStatus.converting:
        return (status.converting, Colors.blue, Icons.sync);
      case DocumentConversionStatus.skipped:
        return (status.notAvailable, Colors.orange, Icons.warning_amber);
      case DocumentConversionStatus.unknown:
        return (status.pending, Colors.grey, Icons.help_outline);
      case null:
        break;
    }
    if (document.extraction?.status == DocumentExtractionStatus.failed) {
      return (status.failed, Colors.red, Icons.error);
    }
    return (status.converted, Colors.green, Icons.check_circle);
  }

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = info(context, document);
    return StatusChip(label: label, color: color, icon: icon);
  }
}
