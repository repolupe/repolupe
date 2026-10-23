import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/extraction.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/repositories/document_status_chip.dart';
import 'package:app/widget/repositories/info_card.dart';
import 'package:flutter/material.dart';

/// The details of a document's conversion: its status, what is pending (started when, why it is skipped), and
/// the extraction the model reads (when it was made, OCR, the error of a failed one).
class DocumentDetailsSheet extends StatelessWidget {
  final RepositoryDocumentDto document;

  const DocumentDetailsSheet({super.key, required this.document});

  static Future<void> show(BuildContext context, {required RepositoryDocumentDto document}) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DocumentDetailsSheet(document: document),
    );
  }

  /// Why a skipped document is left out, like the web explains it.
  static String skipReason(BuildContext context, DocumentSkipReason? reason) => switch (reason) {
    DocumentSkipReason.lfsObjectMissing => context.t.base.documents.details.lfsObjectMissing,
    _ => context.t.base.documents.details.unreadable,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversion = document.conversion;
    final extraction = document.extraction;
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('repository.documents.details'),
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(context.t.base.documents.document, style: theme.textTheme.titleMedium)),
                ],
              ),
            ),
            InfoRow(label: context.t.flutter.documents.details.path, value: document.path),
            InfoRow(
              label: context.t.base.common.status,
              child: Align(
                alignment: Alignment.centerLeft,
                child: DocumentStatusChip(document: document),
              ),
            ),
            if (conversion != null) ..._conversionRows(context, conversion, extraction),
            if (extraction != null) ..._extractionRows(context, extraction, pending: conversion != null),
          ],
        ),
      ),
    );
  }

  /// What is pending: when a running conversion started, why a skipped one waits, or that it is new or the
  /// settings changed.
  List<Widget> _conversionRows(BuildContext context, DocumentConversionDto conversion, DocumentExtractionDto? extraction) {
    final details = context.t.flutter.documents.details;
    switch (conversion.status) {
      case DocumentConversionStatus.converting:
        final startedAt = conversion.startedAt;
        return [
          InfoRow(
            label: details.started,
            value: formatRelative(startedAt),
            tooltip: startedAt == null ? null : formatDateTime(startedAt),
          ),
        ];
      case DocumentConversionStatus.skipped:
        final retryAt = conversion.retryAt;
        return [
          InfoRow(label: details.reason, value: skipReason(context, conversion.skipReason)),
          InfoRow(
            label: details.triedAgain,
            value: formatRelative(retryAt),
            tooltip: retryAt == null ? null : formatDateTime(retryAt),
          ),
        ];
      case DocumentConversionStatus.waiting:
      case DocumentConversionStatus.unknown:
        return [
          InfoRow(
            label: context.t.base.status.waiting,
            value: extraction != null ? details.settingsChanged : details.newDocument,
          ),
        ];
    }
  }

  /// The extraction the model reads: when it was made, whether OCR was used, or why it failed. While another
  /// conversion is [pending], it is the one made with the earlier settings.
  List<Widget> _extractionRows(BuildContext context, DocumentExtractionDto extraction, {required bool pending}) {
    final details = context.t.flutter.documents.details;
    final failed = extraction.status == DocumentExtractionStatus.failed;
    return [
      InfoRow(
        label: pending ? details.convertedEarlier : context.t.base.status.converted,
        value: failed ? details.failedRelative(relative: formatRelative(extraction.extractedAt)) : formatRelative(extraction.extractedAt),
        tooltip: formatDateTime(extraction.extractedAt),
      ),
      if (failed) InfoRow(label: context.t.base.common.error, value: extraction.error ?? context.t.base.common.unknownError),
      if (!failed)
        InfoRow(
          label: 'OCR',
          value: extraction.ocr == true ? details.ocrUsed : details.ocrNotUsed,
        ),
    ];
  }
}
