import 'dart:math';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/config_page.dart';
import 'package:app/service/admin_extraction_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/extraction.dart';
import 'package:app/util/format.dart';
import 'package:app/util/poller.dart';
import 'package:app/widget/repositories/document_details_sheet.dart';
import 'package:app/widget/repositories/document_status_chip.dart';
import 'package:app/widget/repositories/info_card.dart';
import 'package:app/widget/status_chip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// How often the overview and the documents are loaded again while documents are waiting or being converted.
const _pollInterval = Duration(seconds: 5);

/// How many documents are loaded at once, like the web's table.
const _pageSize = 25;

/// Whether a document can be converted again: it failed with the current settings, or is left out for a while.
bool canRetry(RepositoryDocumentDto document) =>
    document.conversion?.status == DocumentConversionStatus.skipped ||
    (document.conversion == null && document.extraction?.status == DocumentExtractionStatus.failed);

/// The document conversion across all repositories, for admins: what it is doing, its totals, and the documents of
/// all repositories by status, with converting a failed one again. Loaded again every few seconds while documents
/// are waiting or being converted.
class ExtractionPage extends StatefulWidget {
  const ExtractionPage({super.key});

  @override
  State<ExtractionPage> createState() => _ExtractionPageState();
}

class _ExtractionPageState extends State<ExtractionPage> with Refena {
  /// `null` until loaded.
  ExtractionOverviewDto? _overview;

  /// The documents loaded so far, of [_filter].
  List<ExtractionDocumentDto> _documents = const [];

  /// How many documents match [_filter] in all.
  int _total = 0;
  DocumentFilter _filter = DocumentFilter.all;

  /// From the start, since the first load follows the first build.
  bool _loading = true;

  /// While more documents are loaded, or the documents of another filter.
  bool _loadingDocuments = false;

  /// The blob of the document being converted again, so only one retry runs at a time.
  String? _retrying;
  late final Poller _poller;
  late final TapGestureRecognizer _configLink;

  @override
  void initState() {
    super.initState();
    _poller = Poller(interval: _pollInterval, needed: _needsPolling, poll: () => _load(quiet: true));
    _configLink = TapGestureRecognizer()..onTap = _openConfig;
    ensureRef((ref) {
      // ignore: discarded_futures
      _load();
    });
  }

  @override
  void dispose() {
    _poller.dispose();
    _configLink.dispose();
    super.dispose();
  }

  bool _needsPolling() {
    final overview = _overview;
    return overview != null && (overview.converting != null || overview.totals.waiting > 0);
  }

  void _openConfig() {
    // ignore: discarded_futures
    ref.global.dispatchAsync(NavigateAction.push(const ConfigPage()));
  }

  /// Loads the overview and the documents shown so far (at least the first page); [quiet] without the progress
  /// indicator and without a snack bar if it fails (polling).
  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final api = ref.redux(apiProvider);
      final overview = await api.dispatchAsyncTakeResult(ApiGetExtractionOverviewAction());
      final page = await api.dispatchAsyncTakeResult(
        ApiListExtractionDocumentsAction(filter: _filter, offset: 0, limit: max(_pageSize, _documents.length)),
      );
      if (mounted) {
        setState(() {
          _overview = overview;
          _documents = page.items;
          _total = page.total;
        });
      }
    } on ClientError catch (e) {
      if (!quiet) {
        ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.extraction.page.loadFailed(error: e.userMessage)));
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

  /// Loads the documents of [_filter] from [offset]: the first page after a filter change, or the next one.
  Future<void> _loadDocuments({required int offset}) async {
    setState(() {
      _loadingDocuments = true;
    });
    try {
      final page = await ref
          .redux(apiProvider)
          .dispatchAsyncTakeResult(ApiListExtractionDocumentsAction(filter: _filter, offset: offset, limit: _pageSize));
      if (mounted) {
        setState(() {
          _documents = offset == 0 ? page.items : [..._documents.take(offset), ...page.items];
          _total = page.total;
        });
      }
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.extraction.page.loadFailed(error: e.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _loadingDocuments = false;
        });
      }
    }
  }

  Future<void> _setFilter(DocumentFilter filter) async {
    if (filter == _filter) {
      return;
    }
    setState(() {
      _filter = filter;
      _documents = const [];
      _total = 0;
    });
    await _loadDocuments(offset: 0);
  }

  Future<void> _retry(ExtractionDocumentDto document) async {
    setState(() {
      _retrying = document.blobOid;
    });
    try {
      final retried = await ref.global.dispatchAsync(RetryDocumentExtractionAction(document.blobOid));
      if (retried && mounted) {
        await _load(quiet: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _retrying = null;
        });
      }
    }
  }

  /// How many documents a filter matches, from the overview's totals (pending ones are waiting or not available).
  int _count(ExtractionTotalsDto totals, DocumentFilter filter) => switch (filter) {
    DocumentFilter.all => totals.documents,
    DocumentFilter.converted => totals.converted,
    DocumentFilter.failed => totals.failed,
    DocumentFilter.pending => totals.waiting + totals.skipped,
  };

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final t = context.t;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final ocrSettings = t.base.admin.extraction.page.ocrSettings(config: '\u0000').split('\u0000');
    return Scaffold(
      appBar: AppBar(title: Text(t.base.admin.extraction.title)),
      body: overview == null
          ? _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('extraction.retry'),
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(t.base.common.retry),
                    ),
                  )
          : ListView(
              key: const ValueKey('extraction.list'),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    t.base.admin.extraction.page.count(count: overview.totals.documents),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(t.base.documents.description, style: muted),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: ocrSettings.first),
                        TextSpan(
                          text: t.base.admin.extraction.page.configLink,
                          style: muted?.copyWith(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
                          recognizer: _configLink,
                          semanticsIdentifier: 'extraction.configLink',
                        ),
                        TextSpan(text: ocrSettings.last),
                      ],
                    ),
                    style: muted,
                  ),
                ),
                if (overview.paused case final paused?) _PausedNotice(paused: paused),
                _StatusCard(overview: overview),
                InfoCard(
                  icon: Icons.file_copy_outlined,
                  title: t.base.documents.title,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final (filter, label) in [
                            (DocumentFilter.all, t.base.documents.statusFilter.all),
                            (DocumentFilter.converted, t.base.status.converted),
                            (DocumentFilter.failed, t.base.status.failed),
                            (DocumentFilter.pending, t.base.status.pending),
                          ])
                            ChoiceChip(
                              key: ValueKey('extraction.filter.${filter.name}'),
                              label: Text('$label (${formatCount(_count(overview.totals, filter))})'),
                              selected: _filter == filter,
                              onSelected: _loadingDocuments ? null : (_) => _setFilter(filter),
                            ),
                        ],
                      ),
                    ),
                    if (_documents.isEmpty && !_loadingDocuments)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(t.base.documents.noData, style: muted),
                      ),
                    for (final document in _documents)
                      _DocumentTile(
                        document: document,
                        retrying: _retrying == document.blobOid,
                        retryEnabled: _retrying == null,
                        onRetry: () => _retry(document),
                      ),
                    if (_loadingDocuments)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_documents.length < _total)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const ValueKey('extraction.more'),
                            onPressed: () => _loadDocuments(offset: _documents.length),
                            icon: const Icon(Icons.expand_more),
                            label: Text(t.flutter.admin.extraction.page.loadMore(remaining: formatCount(_total - _documents.length))),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// That the OCR service is unavailable, until when the conversions are paused, and the service's error.
class _PausedNotice extends StatelessWidget {
  final ExtractionPauseDto paused;

  const _PausedNotice({required this.paused});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final color = theme.colorScheme.onTertiaryContainer;
    return Card(
      key: const ValueKey('extraction.paused'),
      color: theme.colorScheme.tertiaryContainer,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.base.admin.extraction.page.pausedTitle, style: theme.textTheme.titleSmall?.copyWith(color: color)),
                  const SizedBox(height: 4),
                  Tooltip(
                    message: formatRelative(paused.until),
                    child: Text(
                      t.base.admin.extraction.page.pausedUntil(time: formatDateTime(paused.until)),
                      style: theme.textTheme.bodyMedium?.copyWith(color: color),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(paused.reason, style: theme.textTheme.bodySmall?.copyWith(color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the conversion is doing now, the totals by status, and the extractor (the current settings).
class _StatusCard extends StatelessWidget {
  final ExtractionOverviewDto overview;

  const _StatusCard({required this.overview});

  /// What is being converted, like the web says it: the path, in which repository (or attached to a chat), since when.
  static String convertingText(Translations t, ConvertingDocumentDto converting) {
    final page = t.base.admin.extraction.page;
    final started = formatRelative(converting.startedAt);
    if (converting.attachment) {
      return page.convertingAttachment(path: converting.path, started: started);
    }
    final repository = converting.repository;
    if (repository != null) {
      return page.convertingRepository(path: converting.path, repository: repository.name, owner: repository.ownerName, started: started);
    }
    return page.converting(path: converting.path, started: started);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final page = t.base.admin.extraction.page;
    final converting = overview.converting;
    final totals = overview.totals;
    return InfoCard(
      icon: Icons.sync,
      title: t.base.common.status,
      children: [
        InfoRow(
          label: page.now,
          value: converting != null
              ? convertingText(t, converting)
              : overview.paused != null
              ? page.statusPaused
              : totals.waiting > 0
              ? page.statusWaiting
              : page.statusIdle,
          tooltip: converting == null ? null : formatDateTime(converting.startedAt),
        ),
        InfoRow(
          label: t.base.documents.title,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              StatusChip(
                label: page.total(count: formatCount(totals.documents)),
                color: Colors.blueGrey,
                icon: Icons.description_outlined,
              ),
              StatusChip(
                label: page.converted(count: formatCount(totals.converted)),
                color: Colors.green,
                icon: Icons.check_circle,
              ),
              StatusChip(
                label: page.failed(count: formatCount(totals.failed)),
                color: Colors.red,
                icon: Icons.error,
              ),
              StatusChip(
                label: page.waiting(count: formatCount(totals.waiting)),
                color: Colors.grey,
                icon: Icons.schedule,
              ),
              StatusChip(
                label: page.notAvailable(count: formatCount(totals.skipped)),
                color: Colors.orange,
                icon: Icons.warning_amber,
              ),
            ],
          ),
        ),
        InfoRow(label: page.extractor, value: overview.extractor, monospace: true),
      ],
    );
  }
}

/// A document of any repository: its path, its repository with the owner, its status, and converting it again if it
/// failed or is not available. Tapping it shows the details.
class _DocumentTile extends StatelessWidget {
  final ExtractionDocumentDto document;
  final bool retrying;
  final bool retryEnabled;
  final VoidCallback onRetry;

  const _DocumentTile({required this.document, required this.retrying, required this.retryEnabled, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final repository = document.repository;
    return ListTile(
      key: ValueKey('extraction.document.${repository.id}.${document.document.path}'),
      dense: true,
      title: Text(document.document.path, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${repository.name} (${repository.ownerName})', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DocumentStatusChip(document: document.document),
          if (canRetry(document.document))
            retrying
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    key: ValueKey('extraction.document.${repository.id}.${document.document.path}.retry'),
                    icon: const Icon(Icons.restart_alt),
                    tooltip: context.t.base.admin.extraction.page.convertAgain,
                    onPressed: retryEnabled ? onRetry : null,
                  ),
        ],
      ),
      onTap: () => DocumentDetailsSheet.show(context, document: document.document),
    );
  }
}
