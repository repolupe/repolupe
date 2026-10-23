import 'dart:async';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/home_page.dart';
import 'package:app/pages/settings/repositories_page.dart';
import 'package:app/pages/settings/repository_form_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/format.dart';
import 'package:app/util/poller.dart';
import 'package:app/widget/confirm_dialog.dart';
import 'package:app/widget/delete_dialog.dart';
import 'package:app/widget/repositories/info_card.dart';
import 'package:app/widget/repositories/repository_documents_card.dart';
import 'package:app/widget/repositories/repository_users_card.dart';
import 'package:app/widget/repositories/sync_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// How often the repository is loaded again while a sync is pending or running.
const _pollInterval = Duration(seconds: 5);

/// A requested sync only makes the repository due, the scheduler picks it up within a few seconds.
const _syncRequestPollDuration = Duration(seconds: 30);

/// One repository: what it is, its sync, and (for the owner) editing, deleting and syncing it, or leaving it (for a
/// user it is shared with). Loaded again every few seconds while it is syncing. Pops if it no longer exists.
class RepositoryPage extends StatefulWidget {
  final UuidValue id;

  const RepositoryPage({super.key, required this.id});

  @override
  State<RepositoryPage> createState() => _RepositoryPageState();
}

class _RepositoryPageState extends State<RepositoryPage> with Refena {
  /// `null` until it is loaded.
  RepositoryDto? _repository;
  bool _loading = false;
  bool _syncing = false;

  /// Until when the page polls after "Sync now".
  DateTime? _pollUntil;
  late final Poller _poller;

  @override
  void initState() {
    super.initState();
    _poller = Poller(interval: _pollInterval, needed: _needsPolling, poll: () => _load(quiet: true));
    ensureRef((ref) {
      // ignore: discarded_futures
      _load();
    });
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  bool _needsPolling() {
    final repository = _repository;
    final pollUntil = _pollUntil;
    return repository != null && (isSyncing(repository) || (pollUntil != null && DateTime.now().isBefore(pollUntil)));
  }

  /// Loads the repository; [quiet] without the progress indicator and without a snack bar if it fails (polling).
  /// Closes the page if it no longer exists (or is no longer shared with the user).
  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final repository = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiGetRepositoryAction(id: widget.id));
      if (mounted) {
        setState(() {
          _repository = repository;
        });
      }
    } on ClientError catch (e) {
      if (e.code == ErrorCode.notFound) {
        ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.page.notFound));
        _poller.dispose();
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }
      if (!quiet) {
        ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.page.loadFailed(error: e.userMessage)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _poller.update();
      }
    }
  }

  Future<void> _requestSync() async {
    setState(() {
      _syncing = true;
    });
    try {
      await ref.redux(apiProvider).dispatchAsync(ApiSyncRepositoryAction(id: widget.id));
      _pollUntil = DateTime.now().add(_syncRequestPollDuration);
      ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.page.syncRequested));
      await _load();
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.page.syncFailed(error: e.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  Future<void> _edit(RepositoryDto repository) async {
    final updated = await ref.global.dispatchAsync(NavigateAction.push<RepositoryDto>(RepositoryFormPage.edit(repository: repository)));
    if (updated == null || !mounted) {
      return;
    }
    setState(() {
      _repository = updated;
    });
    _poller.update();
    ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.page.updated));
  }

  Future<void> _delete(RepositoryDto repository) async {
    final deleted = await DeleteDialog.show(
      context,
      title: t.base.repositories.page.deleteTitle,
      text: repository.remote == null ? t.base.repositories.page.deleteTextLocal : t.base.repositories.page.deleteText,
      verify: repository.name,
      keyPrefix: 'repository.delete',
      onDelete: () async {
        try {
          await ref.redux(apiProvider).dispatchAsync(ApiDeleteRepositoryAction(id: repository.id));
          return null;
        } on ClientError catch (e) {
          return t.base.repositories.page.deleteFailed(error: e.userMessage);
        }
      },
    );
    if (deleted && mounted) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.page.deleted));
      Navigator.pop(context);
    }
  }

  Future<void> _leave(RepositoryDto repository, UuidValue userId) async {
    final left = await ConfirmDialog.show(
      context,
      title: t.base.repositories.page.leaveTitle,
      text: t.base.repositories.page.leaveText,
      confirmText: t.base.repositories.page.leave,
      confirmIcon: Icons.logout,
      confirmKey: 'repository.leave.confirm',
      onConfirm: () async {
        try {
          await ref.redux(apiProvider).dispatchAsync(ApiRemoveRepositoryUserAction(id: repository.id, userId: userId));
          return null;
        } on ClientError catch (e) {
          return t.base.repositories.page.leaveFailed(error: e.userMessage);
        }
      },
    );
    if (left && mounted) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.page.left));
      Navigator.pop(context);
    }
  }

  /// Starts a new chat that reads only this repository, closing the settings.
  void _ask(RepositoryDto repository) {
    unawaited(ref.global.dispatchAsync(NavigateAction.pushRoot(HomePage(repositoryIds: [repository.id]))));
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    final me = context.watch(meProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(repository?.name ?? context.t.base.common.repository, overflow: TextOverflow.ellipsis)),
      body: repository == null
          ? _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonalIcon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.t.base.common.retry),
                    ),
                  )
          : _Body(
              repository: repository,
              isOwner: me != null && repository.ownerId == me.id,
              canManageSharing: me != null && (repository.ownerId == me.id || me.role == UserRole.admin),
              syncing: _syncing,
              onAsk: () => _ask(repository),
              onEdit: () => _edit(repository),
              onDelete: () => _delete(repository),
              onLeave: me == null ? null : () => _leave(repository, me.id),
              onSync: _requestSync,
              theme: theme,
            ),
    );
  }
}

/// The page once the repository is loaded.
class _Body extends StatelessWidget {
  final RepositoryDto repository;
  final bool isOwner;

  /// Whether the sharing card is shown: the owner and admins manage who the repository is shared with.
  final bool canManageSharing;
  final bool syncing;
  final VoidCallback onAsk;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onLeave;
  final VoidCallback onSync;
  final ThemeData theme;

  const _Body({
    required this.repository,
    required this.isOwner,
    required this.canManageSharing,
    required this.syncing,
    required this.onAsk,
    required this.onEdit,
    required this.onDelete,
    required this.onLeave,
    required this.onSync,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final remote = repository.remote;
    final size = repositorySize(repository);
    final lfsSize = repository.lfsSize;
    final token = remote?.token;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final page = context.t.base.repositories.page;
    return ListView(
      key: const ValueKey('repository.body'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            isOwner
                ? remote != null
                      ? page.ownerIntro
                      : page.ownerIntroLocal
                : page.sharedIntro,
            style: muted,
          ),
        ),
        _MetaRow(label: page.owner, value: isOwner ? page.ownerYou : page.ownerShared),
        _MetaRow(
          label: context.t.base.repositories.size,
          value: formatBytes(size),
          detail: lfsSize != null && lfsSize > 0 ? page.sizeSplit(git: formatBytes(repository.gitSize), lfs: formatBytes(lfsSize)) : null,
          tooltip: size != null && remote != null ? page.sizeTitle(branch: remote.branch) : null,
        ),
        _MetaRow(label: page.created, value: formatRelative(repository.createdAt), detail: formatDateTime(repository.createdAt)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: FilledButton.icon(
            key: const ValueKey('repository.ask'),
            onPressed: onAsk,
            icon: const Icon(Icons.question_answer_outlined),
            label: Text(page.askQuestion),
          ),
        ),
        if (repository.syncStatus == RepositorySyncStatus.failed)
          Card(
            key: const ValueKey('repository.failed'),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 12),
                      Text(
                        page.lastSyncFailed,
                        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    repository.lastError ?? context.t.base.common.unknownError,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
                  ),
                ],
              ),
            ),
          ),
        InfoCard(
          icon: Icons.info_outline,
          title: context.t.base.common.repository,
          actions: [
            if (isOwner) ...[
              TextButton.icon(
                key: const ValueKey('repository.edit'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: Text(context.t.base.common.edit),
              ),
              TextButton.icon(
                key: const ValueKey('repository.delete'),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: Text(context.t.base.common.delete),
              ),
            ] else
              TextButton.icon(
                key: const ValueKey('repository.leave'),
                onPressed: onLeave,
                icon: const Icon(Icons.logout),
                label: Text(page.leave),
              ),
          ],
          children: [
            InfoRow(label: context.t.base.common.name, value: repository.name),
            InfoRow(label: context.t.base.repositories.description, value: repository.description ?? '-'),
            if (remote != null) ...[
              InfoRow(label: context.t.base.repositories.remoteUrl, value: remote.url),
              InfoRow(label: context.t.base.repositories.branch, value: remote.branch),
              InfoRow(
                label: context.t.base.repositories.accessToken,
                value: token == null
                    ? page.tokenNone
                    : token.hint == null
                    ? page.tokenSet
                    : context.t.flutter.repositories.page.tokenSetWithHint(hint: token.hint!),
              ),
            ] else
              InfoRow(label: context.t.base.repositories.remote, value: page.remoteNone),
            InfoRow(
              label: page.writeAccess,
              value: repository.canCommit ? page.writeAccessEnabled : page.writeAccessDisabled,
            ),
          ],
        ),
        InfoCard(
          icon: Icons.sync,
          title: page.sync,
          // A local repository is synced after each commit, there is nothing else to fetch.
          actions: [
            if (isOwner && remote != null)
              FilledButton.icon(
                key: const ValueKey('repository.syncNow'),
                onPressed: syncing ? null : onSync,
                icon: syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
                label: Text(page.syncNow),
              ),
          ],
          children: [
            InfoRow(
              label: context.t.base.common.status,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SyncStatusChip(repository: repository),
              ),
            ),
            InfoRow(label: page.interval, value: remote != null ? formatPollInterval(remote.pollIntervalSeconds) : page.intervalLocal),
            InfoRow(label: page.headCommit, value: shortSha(repository.headCommitSha), tooltip: repository.headCommitSha, monospace: true),
            InfoRow(
              label: page.lastSynced,
              value: formatRelative(repository.lastSyncedAt),
              tooltip: repository.lastSyncedAt == null ? null : formatDateTime(repository.lastSyncedAt!),
            ),
            if (repository.syncStatus == RepositorySyncStatus.syncing)
              InfoRow(
                label: page.syncStarted,
                value: formatRelative(repository.syncStartedAt),
                tooltip: repository.syncStartedAt == null ? null : formatDateTime(repository.syncStartedAt!),
              ),
            InfoRow(
              label: page.nextSync,
              value: formatRelative(repository.nextSyncAt),
              tooltip: repository.nextSyncAt == null ? null : formatDateTime(repository.nextSyncAt!),
            ),
          ],
        ),
        RepositoryDocumentsCard(repositoryId: repository.id, headCommitSha: repository.headCommitSha),
        if (canManageSharing) RepositoryUsersCard(repositoryId: repository.id, allowCommits: repository.allowCommits, local: remote == null),
      ],
    );
  }
}

/// A label and its value above the cards, e.g. the owner, with an optional second line and tooltip.
class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final String? tooltip;

  const _MetaRow({required this.label, required this.value, this.detail, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(value),
        if (detail != null) Text(detail!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: tooltip == null ? content : Tooltip(message: tooltip!, child: content),
            ),
          ),
        ],
      ),
    );
  }
}
