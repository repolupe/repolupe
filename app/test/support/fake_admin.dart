import 'package:app/src/rust/third_party/repolupe/dto/config.dart';
import 'package:app/src/rust/third_party/repolupe/dto/extraction.dart';
import 'package:uuid/uuid.dart';

import 'fake_repository.dart';

/// An `ExtractionOverviewDto`, like `GET /api/v1/document-extraction` returns it. The counts below [documents] should
/// add up to it; [converting] is the document being converted (see [fakeConvertingDocument]), [pausedUntil] with
/// [pauseReason] the pause of the conversions.
ExtractionOverviewDto fakeExtractionOverview({
  String extractor = 'xberg-1/paddle/en/0.5',
  int documents = 0,
  int converted = 0,
  int failed = 0,
  int waiting = 0,
  int skipped = 0,
  ConvertingDocumentDto? converting,
  String? pausedUntil,
  String pauseReason = 'Mistral: 429 Too Many Requests',
}) => ExtractionOverviewDto(
  extractor: extractor,
  converting: converting,
  paused: pausedUntil == null ? null : ExtractionPauseDto(until: DateTime.parse(pausedUntil), reason: pauseReason),
  totals: ExtractionTotalsDto(
    documents: documents,
    converted: converted,
    failed: failed,
    waiting: waiting,
    skipped: skipped,
  ),
);

/// A `ConvertingDocumentDto` of a fake overview: a document of a repository, or an [attachment].
ConvertingDocumentDto fakeConvertingDocument({
  required String path,
  String? repositoryId,
  String repositoryName = 'docs',
  String ownerName = 'alice',
  bool attachment = false,
  String startedAt = '2026-10-21T12:00:00+00:00',
}) => ConvertingDocumentDto(
  repository: repositoryId == null
      ? null
      : RepositoryLabelDto(
          id: UuidValue.fromString(repositoryId),
          name: repositoryName,
          ownerName: ownerName,
          readable: true,
        ),
  path: path,
  attachment: attachment,
  startedAt: DateTime.parse(startedAt),
);

/// An `ExtractionDocumentDto`, as `GET /api/v1/document-extraction/documents` lists them: a document (see
/// [fakeDocument] for its status) with its repository and the blob of its content.
ExtractionDocumentDto fakeExtractionDocument({
  required String path,
  required String repositoryId,
  String repositoryName = 'docs',
  String ownerName = 'alice',
  bool readable = true,
  String? blobOid,
  DocumentConversionStatus? conversion,
  String? startedAt,
  DocumentSkipReason? skipReason,
  String? retryAt,
  DocumentExtractionStatus? extraction = DocumentExtractionStatus.completed,
  bool? ocr = false,
  String? error,
  String extractedAt = '2026-10-21T11:00:00+00:00',
}) => ExtractionDocumentDto(
  repository: RepositoryLabelDto(
    id: UuidValue.fromString(repositoryId),
    name: repositoryName,
    ownerName: ownerName,
    readable: readable,
  ),
  blobOid: blobOid ?? 'blob-$path',
  document: fakeDocument(
    path: path,
    conversion: conversion,
    startedAt: startedAt,
    skipReason: skipReason,
    retryAt: retryAt,
    extraction: extraction,
    ocr: ocr,
    error: error,
    extractedAt: extractedAt,
  ),
);

/// A `ConfigEntryDto`, as `GET /api/v1/config` lists them.
ConfigEntryDto fakeConfigEntry({required String key, String? env, String? override, bool runtime = false}) =>
    ConfigEntryDto(key: key, env: env, overrideValue: override, runtime: runtime);
