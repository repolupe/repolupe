import 'fake_repository.dart';

/// The `ExtractionOverviewDto` JSON of a fake server, like `GET /api/v1/document-extraction` returns it. The counts
/// below [documents] should add up to it; [converting] is a `ConvertingDocumentDto` (see [fakeConvertingDocument]),
/// [pausedUntil] with [pauseReason] the pause of the conversions.
Map<String, dynamic> fakeExtractionOverview({
  String extractor = 'xberg-1/paddle/en/0.5',
  int documents = 0,
  int converted = 0,
  int failed = 0,
  int waiting = 0,
  int skipped = 0,
  Map<String, dynamic>? converting,
  String? pausedUntil,
  String pauseReason = 'Mistral: 429 Too Many Requests',
}) => {
  'extractor': extractor,
  'converting': converting,
  'paused': pausedUntil == null ? null : {'until': pausedUntil, 'reason': pauseReason},
  'totals': {'documents': documents, 'converted': converted, 'failed': failed, 'waiting': waiting, 'skipped': skipped},
};

/// The `ConvertingDocumentDto` JSON of a fake overview: a document of a repository, or an [attachment].
Map<String, dynamic> fakeConvertingDocument({
  required String path,
  String? repositoryId,
  String repositoryName = 'docs',
  String ownerName = 'alice',
  bool attachment = false,
  String startedAt = '2026-10-21T12:00:00+00:00',
}) => {
  'repository': repositoryId == null ? null : {'id': repositoryId, 'name': repositoryName, 'owner_name': ownerName, 'readable': true},
  'path': path,
  'attachment': attachment,
  'started_at': startedAt,
};

/// The `ExtractionDocumentDto` JSON of a fake server, as `GET /api/v1/document-extraction/documents` lists them: a
/// document (see [fakeDocument] for its status) with its repository and the blob of its content.
Map<String, dynamic> fakeExtractionDocument({
  required String path,
  required String repositoryId,
  String repositoryName = 'docs',
  String ownerName = 'alice',
  bool readable = true,
  String? blobOid,
  String? conversion,
  String? startedAt,
  String? skipReason,
  String? retryAt,
  String? extraction = 'COMPLETED',
  bool? ocr = false,
  String? error,
  String extractedAt = '2026-10-21T11:00:00+00:00',
}) => {
  'repository': {'id': repositoryId, 'name': repositoryName, 'owner_name': ownerName, 'readable': readable},
  'blob_oid': blobOid ?? 'blob-$path',
  ...fakeDocument(
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
};

/// The `ConfigEntryDto` JSON of a fake server, as `GET /api/v1/config` lists them.
Map<String, dynamic> fakeConfigEntry({required String key, String? env, String? override, bool runtime = false}) => {
  'key': key,
  'env': env,
  'override': override,
  'runtime': runtime,
};
