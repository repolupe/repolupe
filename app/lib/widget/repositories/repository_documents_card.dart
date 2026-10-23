import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/extraction.dart';
import 'package:app/util/format.dart';
import 'package:app/util/poller.dart';
import 'package:app/widget/repositories/document_details_sheet.dart';
import 'package:app/widget/repositories/document_status_chip.dart';
import 'package:app/widget/repositories/info_card.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// How often the documents are loaded again while some are pending. Conversions take seconds to minutes each.
const _pollInterval = Duration(seconds: 5);

/// How many documents are shown at first, and added by "Show more".
const _pageSize = 10;

/// The documents of the head commit of a repository with their conversion status, filtered by status, with the
/// details of a document on tap. Loaded again every few seconds while documents are pending, and when the head
/// commit changes.
class RepositoryDocumentsCard extends StatefulWidget {
  final UuidValue repositoryId;

  /// The documents are those of this commit, so they are loaded again when it changes.
  final String? headCommitSha;

  const RepositoryDocumentsCard({super.key, required this.repositoryId, required this.headCommitSha});

  @override
  State<RepositoryDocumentsCard> createState() => _RepositoryDocumentsCardState();
}

class _RepositoryDocumentsCardState extends State<RepositoryDocumentsCard> with Refena {
  /// `null` until loaded.
  List<RepositoryDocumentDto>? _documents;
  DateTime? _pausedUntil;
  DocumentFilter _filter = DocumentFilter.all;
  int _shown = _pageSize;

  /// From the start, since the first load follows the first build.
  bool _loading = true;
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
  void didUpdateWidget(covariant RepositoryDocumentsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.headCommitSha != widget.headCommitSha) {
      // ignore: discarded_futures
      _load(quiet: true);
    }
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  bool _needsPolling() => _count(DocumentFilter.pending) > 0;

  int _count(DocumentFilter filter) {
    final documents = _documents ?? const [];
    return filter == DocumentFilter.all ? documents.length : documents.where((d) => documentCategory(d) == filter).length;
  }

  /// Loads the documents; [quiet] without the progress indicator and without a snack bar if it fails (polling).
  Future<void> _load({bool quiet = false}) async {
    setState(() {
      _loading = true;
    });
    try {
      final result = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiListRepositoryDocumentsAction(id: widget.repositoryId));
      if (mounted) {
        setState(() {
          _documents = result.documents;
          _pausedUntil = result.pausedUntil;
        });
      }
    } on ClientError catch (e) {
      if (!quiet) {
        ref.global.dispatch(ShowSnackBarAction(message: t.base.documents.loadFailed(error: e.userMessage)));
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

  void _setFilter(DocumentFilter filter) {
    setState(() {
      _filter = filter;
      _shown = _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final documents = _documents;
    final pausedUntil = _pausedUntil;
    final filtered = documents == null
        ? const <RepositoryDocumentDto>[]
        : _filter == DocumentFilter.all
        ? documents
        : documents.where((d) => documentCategory(d) == _filter).toList();
    return InfoCard(
      icon: Icons.file_copy_outlined,
      title: context.t.base.documents.title,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(context.t.base.documents.description, style: muted),
        ),
        if (pausedUntil != null && _count(DocumentFilter.pending) > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: theme.colorScheme.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Tooltip(
                    message: formatRelative(pausedUntil),
                    child: Text(context.t.base.documents.card.paused(time: formatDateTime(pausedUntil))),
                  ),
                ),
              ],
            ),
          ),
        if (documents == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('repository.documents.retry'),
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.t.base.common.retry),
                    ),
                  ),
          )
        else if (documents.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(widget.headCommitSha == null ? context.t.flutter.documents.notSynced : context.t.flutter.documents.noDocuments, style: muted),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (filter, label) in [
                  (DocumentFilter.all, context.t.base.documents.statusFilter.all),
                  (DocumentFilter.converted, context.t.base.status.converted),
                  (DocumentFilter.failed, context.t.base.status.failed),
                  (DocumentFilter.pending, context.t.base.status.pending),
                ])
                  ChoiceChip(
                    key: ValueKey('repository.documents.filter.${filter.name}'),
                    label: Text('$label (${formatCount(_count(filter))})'),
                    selected: _filter == filter,
                    onSelected: (_) => _setFilter(filter),
                  ),
              ],
            ),
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(context.t.base.documents.noData, style: muted),
            ),
          for (final document in filtered.take(_shown))
            ListTile(
              key: ValueKey('repository.documents.${document.path}'),
              dense: true,
              title: Text(document.path, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: DocumentStatusChip(document: document),
              onTap: () => DocumentDetailsSheet.show(context, document: document),
            ),
          if (filtered.length > _shown)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('repository.documents.more'),
                  onPressed: () {
                    setState(() {
                      _shown += _pageSize;
                    });
                  },
                  icon: const Icon(Icons.expand_more),
                  label: Text(context.t.flutter.documents.showMore(remaining: formatCount(filtered.length - _shown))),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
