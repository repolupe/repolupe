import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/repository_form_page.dart';
import 'package:app/pages/settings/repository_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:app/util/format.dart';
import 'package:app/util/poller.dart';
import 'package:app/widget/repositories/repository_kind_sheet.dart';
import 'package:app/widget/repositories/sync_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// How often the list is loaded again while a repository is waiting for or in a sync.
const _pollInterval = Duration(seconds: 5);

/// Whether the repository is waiting for or in a sync, so its status will change soon.
bool isSyncing(RepositoryDto repository) =>
    repository.syncStatus == RepositorySyncStatus.pending || repository.syncStatus == RepositorySyncStatus.syncing;

/// Git and LFS together in bytes, like GitLab and Forgejo show it, `null` until the first sync.
int? repositorySize(RepositoryDto repository) {
  final (gitSize, lfsSize) = (repository.gitSize, repository.lfsSize);
  return gitSize == null || lfsSize == null ? null : gitSize + lfsSize;
}

/// The repositories the user owns or that are shared with them, with a search, each opening its page, and a button
/// to create one. Loaded again every few seconds while one is syncing.
class RepositoriesPage extends StatefulWidget {
  const RepositoriesPage({super.key});

  @override
  State<RepositoriesPage> createState() => _RepositoriesPageState();
}

class _RepositoriesPageState extends State<RepositoriesPage> with Refena {
  /// `null` until they are loaded.
  List<RepositoryDto>? _repositories;
  bool _loading = false;
  String _query = '';
  late final Poller _poller;

  @override
  void initState() {
    super.initState();
    _poller = Poller(
      interval: _pollInterval,
      needed: () => _repositories?.any(isSyncing) ?? false,
      poll: () => _load(quiet: true),
    );
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

  /// Loads the repositories; [quiet] without the progress indicator and without a snack bar if it fails (polling).
  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final repositories = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiListRepositoriesAction());
      if (mounted) {
        setState(() {
          _repositories = repositories;
        });
      }
    } on ClientError catch (e) {
      if (!quiet) {
        ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.listPage.loadFailed(error: e.userMessage)));
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

  /// Asks for the kind, then opens the form; the list is loaded again with the new repository.
  Future<void> _create() async {
    final kind = await RepositoryKindSheet.show(context);
    if (kind == null || !mounted) {
      return;
    }
    final created = await ref.global.dispatchAsync(NavigateAction.push<RepositoryDto>(RepositoryFormPage.create(kind: kind)));
    if (created == null || !mounted) {
      return;
    }
    ref.global.dispatch(
      ShowSnackBarAction(
        message: kind == RepositoryKind.remote ? t.base.repositories.listPage.added : t.flutter.repositories.listPage.addedLocal,
      ),
    );
    await _load(quiet: true);
  }

  /// Opens the repository's page; the list is loaded again when it closes (it may have been changed or deleted).
  Future<void> _open(RepositoryDto repository) async {
    await ref.global.dispatchAsync(NavigateAction.push(RepositoryPage(id: repository.id)));
    if (mounted) {
      await _load(quiet: true);
    }
  }

  List<RepositoryDto> _filtered(List<RepositoryDto> repositories) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return repositories;
    }
    return repositories
        .where(
          (r) =>
              r.name.toLowerCase().contains(query) ||
              (r.remote?.url.toLowerCase().contains(query) ?? false) ||
              (r.description?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final repositories = _repositories;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.t.base.repositories.title)),
      floatingActionButton: repositories == null || repositories.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('repositories.new'),
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: Text(context.t.base.repositories.newRepository),
            ),
      body: repositories == null
          ? _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonalIcon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.t.base.common.retry),
                    ),
                  )
          : repositories.isEmpty
          ? _EmptyState(onCreate: _create)
          : ListView(
              key: const ValueKey('repositories.list'),
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    context.t.base.repositories.listPage.count(count: repositories.length),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    context.t.base.repositories.listPage.description,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    key: const ValueKey('repositories.search'),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: context.t.base.common.search,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                  ),
                ),
                for (final repository in _filtered(repositories)) _RepositoryTile(repository: repository, onTap: () => _open(repository)),
                if (_filtered(repositories).isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      context.t.base.repositories.listPage.noMatch,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// A repository: its name, remote (URL and branch) or "Local", size and sync status.
class _RepositoryTile extends StatelessWidget {
  final RepositoryDto repository;
  final VoidCallback onTap;

  const _RepositoryTile({required this.repository, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final remote = repository.remote;
    return ListTile(
      key: ValueKey('repositories.${repository.id}'),
      leading: Icon(remote == null ? Icons.dns_outlined : Icons.cloud_sync_outlined),
      title: Text(repository.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(remote == null ? context.t.base.repositories.local : '${remote.url} (${remote.branch})', maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(formatBytes(repositorySize(repository))),
        ],
      ),
      isThreeLine: true,
      trailing: SyncStatusChip(repository: repository),
      onTap: onTap,
    );
  }
}

/// Shown while the user has no repositories.
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.source, size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(context.t.base.repositories.listPage.emptyTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              context.t.base.repositories.listPage.emptyText,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('repositories.new'),
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(context.t.base.repositories.newRepository),
            ),
          ],
        ),
      ),
    );
  }
}
