/// The `RepositoryDto` JSON of a fake server, like `GET /api/v1/repositories/{id}` returns it. A [local] repository
/// has no remote; otherwise [url], [branch], [pollIntervalSeconds] and the token ([hasToken] with its [tokenHint]).
Map<String, dynamic> fakeRepository({
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
  String syncStatus = 'READY',
  String? syncStartedAt,
  String? headCommitSha = '0123456789abcdef0123456789abcdef01234567',
  String? lastSyncedAt = '2026-10-21T12:00:00+00:00',
  int? gitSize = 12300,
  int? lfsSize = 0,
  String? lastError,
  String? nextSyncAt = '2026-10-21T12:15:00+00:00',
}) => {
  'id': id,
  'owner_id': ownerId,
  'name': name,
  'description': description,
  'remote': local
      ? null
      : {
          'url': url,
          'branch': branch,
          'poll_interval_seconds': pollIntervalSeconds,
          'token': hasToken ? {'hint': tokenHint} : null,
        },
  'allow_commits': allowCommits,
  'can_commit': canCommit,
  'sync_status': syncStatus,
  'sync_started_at': syncStartedAt,
  'head_commit_sha': headCommitSha,
  'last_synced_at': lastSyncedAt,
  'git_size': gitSize,
  'lfs_size': lfsSize,
  'last_error': lastError,
  'next_sync_at': nextSyncAt,
  'created_at': '2026-10-20T12:00:00+00:00',
  'updated_at': '2026-10-21T12:00:00+00:00',
};

/// The `RepositoryDocumentDto` JSON of a fake server, as `GET /api/v1/repositories/{id}/documents` lists them.
/// [conversion] is the pending status (`WAITING`, `CONVERTING`, `SKIPPED`) or `null` once converted with the
/// current settings; [extraction] the stored result (`COMPLETED`, `FAILED`) or `null` if never converted.
Map<String, dynamic> fakeDocument({
  required String path,
  String? conversion,
  String? startedAt,
  String? skipReason,
  String? retryAt,
  String? extraction = 'COMPLETED',
  bool? ocr = false,
  String? error,
  String extractedAt = '2026-10-21T11:00:00+00:00',
}) => {
  'path': path,
  'extraction': extraction == null ? null : {'status': extraction, 'ocr': ocr, 'error': error, 'extracted_at': extractedAt},
  'conversion': conversion == null ? null : {'status': conversion, 'started_at': startedAt, 'skip_reason': skipReason, 'retry_at': retryAt},
};

/// The `RepositoryUserDto` JSON of a fake server, as `GET /api/v1/repositories/{id}/users` lists them.
Map<String, dynamic> fakeRepositoryUser({
  required String userId,
  required String userName,
  String? email,
  bool canCommit = false,
  String createdAt = '2026-10-20T12:00:00+00:00',
}) => {'user_id': userId, 'user_name': userName, 'email': email, 'can_commit': canCommit, 'created_at': createdAt};
