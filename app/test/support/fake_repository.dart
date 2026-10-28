import 'package:app/src/rust/third_party/repolupe/dto/extraction.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:uuid/uuid.dart';

/// A `RepositoryDto`, like `GET /api/v1/repositories/{id}` returns it. A [local] repository has no remote; otherwise
/// [url], [branch], [pollIntervalSeconds] and the token ([hasToken] with its [tokenHint]).
RepositoryDto fakeRepository({
  required String id,
  required String ownerId,
  String name = 'docs',
  String? description,
  bool local = false,
  String url = 'https://github.com/acme/docs.git',
  String branch = 'main',
  int pollIntervalSeconds = 900,
  bool hasToken = false,
  String? tokenHint,
  bool allowCommits = true,
  bool canCommit = true,
  RepositorySyncStatus syncStatus = RepositorySyncStatus.ready,
  String? syncStartedAt,
  String? headCommitSha = '0123456789abcdef0123456789abcdef01234567',
  String? lastSyncedAt = '2026-10-21T12:00:00+00:00',
  int? gitSize = 12300,
  int? lfsSize = 0,
  String? lastError,
  String? nextSyncAt = '2026-10-21T12:15:00+00:00',
}) => RepositoryDto(
  id: UuidValue.fromString(id),
  ownerId: UuidValue.fromString(ownerId),
  name: name,
  description: description,
  remote: local
      ? null
      : RemoteSettingsDto(
          url: url,
          branch: branch,
          pollIntervalSeconds: pollIntervalSeconds,
          token: hasToken ? RepositoryTokenDto(hint: tokenHint) : null,
        ),
  allowCommits: allowCommits,
  canCommit: canCommit,
  syncStatus: syncStatus,
  syncStartedAt: _parse(syncStartedAt),
  headCommitSha: headCommitSha,
  lastSyncedAt: _parse(lastSyncedAt),
  gitSize: gitSize,
  lfsSize: lfsSize,
  lastError: lastError,
  nextSyncAt: _parse(nextSyncAt),
  createdAt: DateTime.utc(2026, 10, 20, 12),
  updatedAt: DateTime.utc(2026, 10, 21, 12),
);

/// A `RepositoryDocumentDto`, as `GET /api/v1/repositories/{id}/documents` lists them. [conversion] is the pending
/// status or `null` once converted with the current settings; [extraction] the stored result or `null` if never
/// converted.
RepositoryDocumentDto fakeDocument({
  required String path,
  DocumentConversionStatus? conversion,
  String? startedAt,
  DocumentSkipReason? skipReason,
  String? retryAt,
  DocumentExtractionStatus? extraction = DocumentExtractionStatus.completed,
  bool? ocr = false,
  String? error,
  String extractedAt = '2026-10-21T11:00:00+00:00',
}) => RepositoryDocumentDto(
  path: path,
  extraction: extraction == null
      ? null
      : DocumentExtractionDto(
          status: extraction,
          ocr: ocr,
          error: error,
          extractedAt: DateTime.parse(extractedAt),
        ),
  conversion: conversion == null
      ? null
      : DocumentConversionDto(
          status: conversion,
          startedAt: _parse(startedAt),
          skipReason: skipReason,
          retryAt: _parse(retryAt),
        ),
);

/// A `RepositoryUserDto`, as `GET /api/v1/repositories/{id}/users` lists them.
RepositoryUserDto fakeRepositoryUser({
  required String userId,
  required String userName,
  String? email,
  bool canCommit = false,
  String createdAt = '2026-10-20T12:00:00+00:00',
}) => RepositoryUserDto(
  userId: UuidValue.fromString(userId),
  userName: userName,
  email: email,
  canCommit: canCommit,
  createdAt: DateTime.parse(createdAt),
);

DateTime? _parse(String? timestamp) => timestamp == null ? null : DateTime.parse(timestamp);
