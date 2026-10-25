import 'package:app/gen/strings.g.dart';
import 'package:app/service/admin_llm_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// How [RemoteModelsSheet] was closed.
enum RemoteModelsOutcome {
  /// Nothing was added.
  dismissed,

  /// At least one model was added, so the providers should be loaded again.
  added,

  /// The server did not list its models; the admin wants to add one by name instead.
  addByName,
}

/// The models the server of [provider] offers, to choose the ones to add (the ones the provider already has are
/// marked). They are added one after the other, so the first becomes the default if there is none.
class RemoteModelsSheet extends StatefulWidget {
  final LlmProviderDto provider;

  /// Whether the first model added becomes the default, i.e. there is none yet.
  final bool becomesDefault;

  /// Closes the sheet by itself if the server lists no models or the request fails (after creating a provider,
  /// where the models are only offered if the server lists them).
  final bool closeIfNone;

  const RemoteModelsSheet({super.key, required this.provider, required this.becomesDefault, this.closeIfNone = false});

  static Future<RemoteModelsOutcome> show(
    BuildContext context, {
    required LlmProviderDto provider,
    required bool becomesDefault,
    bool closeIfNone = false,
  }) async {
    final outcome = await showModalBottomSheet<RemoteModelsOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => RemoteModelsSheet(provider: provider, becomesDefault: becomesDefault, closeIfNone: closeIfNone),
    );
    return outcome ?? RemoteModelsOutcome.dismissed;
  }

  @override
  State<RemoteModelsSheet> createState() => _RemoteModelsSheetState();
}

class _RemoteModelsSheetState extends State<RemoteModelsSheet> with Refena {
  bool _fetching = true;
  String? _error;
  List<RemoteModelDto> _models = [];
  String _query = '';
  final _selected = <String>{};

  /// The API names the provider has, including the ones added here.
  late final _added = widget.provider.models.map((m) => m.apiName).toSet();
  bool _adding = false;

  /// How many of the last selection were added and the first error, if some failed, until the next try.
  String? _addError;

  /// Whether a model was added, so closing the sheet reports it.
  bool _anyAdded = false;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      // ignore: discarded_futures
      _fetch();
    });
  }

  Future<void> _fetch() async {
    setState(() {
      _fetching = true;
      _error = null;
    });
    List<RemoteModelDto> models = [];
    String? error;
    try {
      models = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiListRemoteModelsAction(providerId: widget.provider.id));
    } on ClientError catch (e) {
      error = e.userMessage;
    }
    if (!mounted) {
      return;
    }
    if (widget.closeIfNone && (error != null || models.isEmpty)) {
      Navigator.pop(context, RemoteModelsOutcome.dismissed);
      return;
    }
    setState(() {
      _models = models;
      _error = error;
      _fetching = false;
    });
  }

  List<RemoteModelDto> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return _models;
    }
    return _models.where((m) => m.apiName.toLowerCase().contains(query) || (m.displayName?.toLowerCase().contains(query) ?? false)).toList();
  }

  /// The models shown that can be selected.
  List<RemoteModelDto> get _selectable => _filtered.where((m) => !_added.contains(m.apiName)).toList();

  bool get _allSelected => _selectable.isNotEmpty && _selectable.every((m) => _selected.contains(m.apiName));
  bool get _someSelected => !_allSelected && _selectable.any((m) => _selected.contains(m.apiName));

  void _toggleAll() {
    setState(() {
      final select = !_allSelected;
      for (final model in _selectable) {
        if (select) {
          _selected.add(model.apiName);
        } else {
          _selected.remove(model.apiName);
        }
      }
    });
  }

  Future<void> _add() async {
    // Models added meanwhile, e.g. by another admin, are skipped.
    final models = _models.where((m) => _selected.contains(m.apiName) && !_added.contains(m.apiName)).toList();
    setState(() {
      _adding = true;
      _addError = null;
    });
    try {
      final result = await ref.global.dispatchAsync(AddRemoteModelsAction(providerId: widget.provider.id, models: models));
      if (!mounted) {
        return;
      }
      if (result.added.isNotEmpty) {
        _anyAdded = true;
      }
      if (result.error == null) {
        Navigator.pop(context, RemoteModelsOutcome.added);
        return;
      }
      // The ones that were added are marked, the failed ones stay selected for another try.
      setState(() {
        _added.addAll(result.added);
        _selected.removeAll(result.added);
        _addError = result.error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _adding = false;
        });
      }
    }
  }

  void _close() {
    Navigator.pop(context, _anyAdded ? RemoteModelsOutcome.added : RemoteModelsOutcome.dismissed);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final dialog = t.base.admin.llm.remoteModelsDialog;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final error = _error;
    final filtered = _filtered;
    final selectable = _selectable;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(dialog.title(name: widget.provider.name), style: theme.textTheme.titleMedium),
          ),
          if (_fetching)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(dialog.fetching, style: muted),
                ],
              ),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    key: const ValueKey('remoteModels.error'),
                    color: theme.colorScheme.errorContainer,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(error, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(dialog.addByNameHint, style: muted),
                ],
              ),
            )
          else if (_models.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(dialog.noModels, style: muted),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(dialog.intro, style: muted),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: TextField(
                key: const ValueKey('remoteModels.search'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: t.base.common.search,
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
            if (selectable.isNotEmpty)
              CheckboxListTile(
                key: const ValueKey('remoteModels.selectAll'),
                value: _allSelected ? true : (_someSelected ? null : false),
                tristate: true,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_query.trim().isEmpty ? dialog.selectAll : dialog.selectAllMatches(count: selectable.length)),
                onChanged: _adding ? null : (_) => _toggleAll(),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final model in filtered)
                    CheckboxListTile(
                      key: ValueKey('remoteModels.${model.apiName}'),
                      value: _added.contains(model.apiName) || _selected.contains(model.apiName),
                      enabled: !_adding && !_added.contains(model.apiName),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(model.displayName ?? model.apiName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: model.displayName == null
                          ? null
                          : Text(
                              model.apiName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Courier']),
                            ),
                      secondary: _added.contains(model.apiName) ? Chip(label: Text(t.base.common.added), visualDensity: VisualDensity.compact) : null,
                      onChanged: (_) {
                        setState(() {
                          if (!_selected.remove(model.apiName)) {
                            _selected.add(model.apiName);
                          }
                        });
                      },
                    ),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(dialog.noMatch(query: _query.trim()), style: muted),
                    ),
                ],
              ),
            ),
            if (widget.becomesDefault && _selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  dialog.becomesDefault,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
          if (_addError case final addError?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InlineError(addError, key: const ValueKey('remoteModels.addError')),
            ),
          Padding(
            // useSafeArea only covers the top.
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.paddingOf(context).bottom),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                if (error != null)
                  TextButton.icon(
                    key: const ValueKey('remoteModels.retry'),
                    onPressed: _fetch,
                    icon: const Icon(Icons.refresh),
                    label: Text(t.base.common.retry),
                  ),
                TextButton(
                  key: const ValueKey('remoteModels.cancel'),
                  onPressed: _adding ? null : _close,
                  child: Text(t.base.common.cancel),
                ),
                if (!_fetching && (error != null || _models.isEmpty))
                  FilledButton.icon(
                    key: const ValueKey('remoteModels.addByName'),
                    onPressed: () => Navigator.pop(context, RemoteModelsOutcome.addByName),
                    icon: const Icon(Icons.add),
                    label: Text(dialog.addByName),
                  )
                else
                  FilledButton.icon(
                    key: const ValueKey('remoteModels.add'),
                    onPressed: _fetching || _adding || _selected.isEmpty ? null : _add,
                    icon: _adding ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
                    label: Text(dialog.addModels(count: _selected.length)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
