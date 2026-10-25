import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/llm_model_form_page.dart';
import 'package:app/pages/settings/admin/llm_provider_form_page.dart';
import 'package:app/service/admin_llm_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/admin/remote_models_sheet.dart';
import 'package:app/widget/confirm_dialog.dart';
import 'package:app/widget/delete_dialog.dart';
import 'package:app/widget/repositories/info_card.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The color of the star of the default model.
const _starColor = Color(0xFFFFA000);

/// Stands for the star in a translated text, see [_withStar].
const _starMarker = '\u0000';

/// [text] with the star of the default model in place of [_starMarker].
InlineSpan _withStar(String text) {
  final parts = text.split(_starMarker);
  return TextSpan(
    children: [
      for (var i = 0; i < parts.length; i++) ...[
        if (i > 0)
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(Icons.star, size: 16, color: _starColor),
          ),
        TextSpan(text: parts[i]),
      ],
    ],
  );
}

/// The LLM providers with their models, for admins: creating, editing and deleting them, adding the models a server
/// lists, and choosing the default model (the star).
class LlmPage extends StatefulWidget {
  const LlmPage({super.key});

  @override
  State<LlmPage> createState() => _LlmPageState();
}

class _LlmPageState extends State<LlmPage> with Refena {
  /// `null` until they are loaded.
  List<LlmProviderDto>? _providers;
  bool _loading = false;

  /// While a request of the page runs (setting the default), so the stars don't change meanwhile.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      // ignore: discarded_futures
      _load();
    });
  }

  /// Loads the providers; [quiet] without the progress indicator (after a change, when the list is shown already).
  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final providers = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiListLlmProvidersAction());
      if (mounted) {
        setState(() {
          _providers = providers;
        });
      }
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.llm.page.loadFailed(error: e.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  int get _modelCount => _providers?.fold<int>(0, (sum, p) => sum + p.models.length) ?? 0;
  bool get _hasDefault => _providers?.any((p) => p.models.any((m) => m.isDefault)) ?? false;

  /// Creates a provider, then offers the models its server lists (only if it lists them).
  Future<void> _createProvider() async {
    final created = await ref.global.dispatchAsync(NavigateAction.push<LlmProviderDto>(const LlmProviderFormPage.create()));
    if (created == null || !mounted) {
      return;
    }
    await _load(quiet: true);
    if (mounted) {
      await _fetchModels(created, closeIfNone: true);
    }
  }

  Future<void> _editProvider(LlmProviderDto provider) async {
    final updated = await ref.global.dispatchAsync(NavigateAction.push<LlmProviderDto>(LlmProviderFormPage.edit(provider: provider)));
    if (updated != null && mounted) {
      await _load(quiet: true);
    }
  }

  Future<void> _deleteProvider(LlmProviderDto provider) async {
    final page = context.t.base.admin.llm.page;
    final deleted = await DeleteDialog.show(
      context,
      title: page.deleteProviderTitle,
      text:
          page.deleteProviderText(count: provider.models.length, name: provider.name) +
          (provider.models.any((m) => m.isDefault) ? '\n\n${page.deleteProviderHasDefault}' : ''),
      verify: provider.name,
      keyPrefix: 'llm.provider.delete',
      onDelete: () => ref.global.dispatchAsync(DeleteLlmProviderAction(provider.id)),
    );
    if (deleted && mounted) {
      await _load(quiet: true);
    }
  }

  /// Shows the models the server of [provider] lists; the providers are loaded again if some were added. If the
  /// server does not list them, the admin can add one by name instead.
  Future<void> _fetchModels(LlmProviderDto provider, {bool closeIfNone = false}) async {
    final outcome = await RemoteModelsSheet.show(context, provider: provider, becomesDefault: !_hasDefault, closeIfNone: closeIfNone);
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case RemoteModelsOutcome.dismissed:
        break;
      case RemoteModelsOutcome.added:
        await _load(quiet: true);
      case RemoteModelsOutcome.addByName:
        await _createModel(provider);
    }
  }

  Future<void> _createModel(LlmProviderDto provider) async {
    final created = await ref.global.dispatchAsync(
      NavigateAction.push<LlmModelDto>(LlmModelFormPage.create(provider: provider, becomesDefault: !_hasDefault)),
    );
    if (created != null && mounted) {
      await _load(quiet: true);
    }
  }

  Future<void> _editModel(LlmProviderDto provider, LlmModelDto model) async {
    final updated = await ref.global.dispatchAsync(NavigateAction.push<LlmModelDto>(LlmModelFormPage.edit(provider: provider, model: model)));
    if (updated != null && mounted) {
      await _load(quiet: true);
    }
  }

  Future<void> _deleteModel(LlmModelDto model) async {
    final page = context.t.base.admin.llm.page;
    final deleted = await ConfirmDialog.show(
      context,
      title: page.deleteModelTitle,
      text:
          '${page.deleteModelText(name: model.displayName ?? model.apiName)}'
          '${model.isDefault ? '\n\n${page.deleteModelIsDefault}' : ''}'
          '\n\n${page.kContinue}',
      confirmText: context.t.base.common.delete,
      confirmIcon: Icons.delete,
      confirmKey: 'llm.model.delete.confirm',
      onConfirm: () => ref.global.dispatchAsync(DeleteLlmModelAction(model.id)),
    );
    if (deleted && mounted) {
      await _load(quiet: true);
    }
  }

  Future<void> _setDefault(LlmModelDto model) async {
    setState(() {
      _busy = true;
    });
    try {
      await ref.global.dispatchAsync(SetDefaultLlmModelAction(model.id));
    } finally {
      // Also after errors, e.g. UNKNOWN_MODEL when another admin deleted the model.
      if (mounted) {
        setState(() {
          _busy = false;
        });
        await _load(quiet: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final providers = _providers;
    final t = context.t;
    final page = t.base.admin.llm.page;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final modelCount = _modelCount;
    return Scaffold(
      appBar: AppBar(title: Text(t.base.admin.llm.title)),
      floatingActionButton: providers == null || providers.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('llm.newProvider'),
              onPressed: _createProvider,
              icon: const Icon(Icons.add),
              label: Text(t.base.admin.llm.newProvider),
            ),
      body: providers == null
          ? _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonalIcon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(t.base.common.retry),
                    ),
                  )
          : providers.isEmpty
          ? _EmptyState(onCreate: _createProvider)
          : ListView(
              key: const ValueKey('llm.list'),
              padding: EdgeInsets.only(bottom: 88 + MediaQuery.paddingOf(context).bottom),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(page.count(count: modelCount), style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(page.providerIntro, style: muted),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(page.modelsIntro, style: muted),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text.rich(_withStar(page.defaultIntro(icon: _starMarker)), style: muted),
                ),
                if (modelCount == 0)
                  _Notice(key: const ValueKey('llm.noModels'), text: page.noModels)
                else if (!_hasDefault)
                  _Notice(
                    key: const ValueKey('llm.noDefault'),
                    warning: true,
                    text: page.noDefault(icon: _starMarker),
                  ),
                for (final provider in providers)
                  _ProviderCard(
                    provider: provider,
                    busy: _busy,
                    onEdit: () => _editProvider(provider),
                    onDelete: () => _deleteProvider(provider),
                    onFetchModels: () => _fetchModels(provider),
                    onAddModel: () => _createModel(provider),
                    onEditModel: (model) => _editModel(provider, model),
                    onDeleteModel: _deleteModel,
                    onSetDefault: _setDefault,
                  ),
              ],
            ),
    );
  }
}

/// The page without providers: nobody can ask questions until a model is set up.
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(t.base.admin.llm.page.emptyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              t.base.admin.llm.page.emptyText,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('llm.empty.newProvider'),
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(t.base.admin.llm.newProvider),
            ),
          ],
        ),
      ),
    );
  }
}

/// A note above the providers: that there are no models, or no default model ([warning]).
class _Notice extends StatelessWidget {
  /// With [_starMarker] for the star of the default model.
  final String text;
  final bool warning;

  const _Notice({super.key, required this.text, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = warning ? theme.colorScheme.tertiaryContainer : theme.colorScheme.secondaryContainer;
    final onColor = warning ? theme.colorScheme.onTertiaryContainer : theme.colorScheme.onSecondaryContainer;
    return Card(
      color: color,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(warning ? Icons.warning_amber : Icons.info_outline, color: onColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(_withStar(text), style: theme.textTheme.bodyMedium?.copyWith(color: onColor)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A provider: its settings, its models, and what can be done with them.
class _ProviderCard extends StatelessWidget {
  final LlmProviderDto provider;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onFetchModels;
  final VoidCallback onAddModel;
  final void Function(LlmModelDto model) onEditModel;
  final void Function(LlmModelDto model) onDeleteModel;
  final void Function(LlmModelDto model) onSetDefault;

  const _ProviderCard({
    required this.provider,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onFetchModels,
    required this.onAddModel,
    required this.onEditModel,
    required this.onDeleteModel,
    required this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final page = t.base.admin.llm.page;
    final providerDialog = t.base.admin.llm.providerDialog;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final apiKey = provider.apiKey;
    return InfoCard(
      key: ValueKey('llm.provider.${provider.id}'),
      icon: Icons.dns_outlined,
      title: provider.name,
      trailing: PopupMenuButton<String>(
        key: ValueKey('llm.provider.${provider.id}.menu'),
        tooltip: t.base.common.actions,
        onSelected: (value) => switch (value) {
          'edit' => onEdit(),
          'delete' => onDelete(),
          _ => null,
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            key: ValueKey('llm.provider.${provider.id}.edit'),
            value: 'edit',
            child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(page.editProvider), contentPadding: EdgeInsets.zero),
          ),
          PopupMenuItem(
            key: ValueKey('llm.provider.${provider.id}.delete'),
            value: 'delete',
            child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(page.deleteProvider), contentPadding: EdgeInsets.zero),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          key: ValueKey('llm.provider.${provider.id}.fetchModels'),
          onPressed: onFetchModels,
          icon: const Icon(Icons.cloud_download_outlined),
          label: Text(page.fetchModels),
        ),
        TextButton.icon(
          key: ValueKey('llm.provider.${provider.id}.addModel'),
          onPressed: onAddModel,
          icon: const Icon(Icons.add),
          label: Text(page.addModel),
        ),
      ],
      children: [
        InfoRow(label: providerDialog.apiFormat, value: apiFormatLabel(provider.apiFormat)),
        InfoRow(label: providerDialog.baseUrl, value: provider.baseUrl, monospace: true),
        InfoRow(
          label: providerDialog.apiKey,
          value: apiKey == null
              ? t.flutter.admin.llm.page.apiKeyNone
              : (apiKey.hint != null ? '•••• ${apiKey.hint}' : t.base.repositories.page.tokenSet),
        ),
        InfoRow(label: providerDialog.currency, value: provider.currency ?? t.flutter.admin.llm.page.currencyNone),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(t.flutter.admin.llm.page.models, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        if (provider.models.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(page.noModelsYet, style: muted),
          ),
        for (final model in provider.models)
          _ModelTile(
            model: model,
            currency: provider.currency,
            busy: busy,
            onTap: () => onEditModel(model),
            onDelete: () => onDeleteModel(model),
            onSetDefault: () => onSetDefault(model),
          ),
      ],
    );
  }
}

/// A model: the star (filled for the default model, else making it the default), its names, its prices, and
/// deleting it. Tapping it edits it.
class _ModelTile extends StatelessWidget {
  final LlmModelDto model;

  /// The provider's currency, `null` if its models have no prices.
  final String? currency;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  const _ModelTile({
    required this.model,
    required this.currency,
    required this.busy,
    required this.onTap,
    required this.onDelete,
    required this.onSetDefault,
  });

  /// E.g. `$3.00 in / $15.00 out`, or that the prices are not set.
  String _prices(Translations t) {
    final currency = this.currency;
    final input = model.inputPrice;
    final output = model.outputPrice;
    if (currency == null || input == null || output == null) {
      return '${t.base.admin.llm.pricePerMillion}: ${t.base.admin.llm.page.notSet}';
    }
    return t.base.admin.llm.page.price(input: formatPrice(input, currency), output: formatPrice(output, currency));
  }

  /// E.g. `Cache read $0.30, cache write $3.75`, only if a cache price differs from the input price.
  String? _cachePrices(Translations t) {
    final currency = this.currency;
    final input = model.inputPrice;
    if (currency == null || input == null || (model.cacheReadPrice == null && model.cacheWritePrice == null)) {
      return null;
    }
    return t.base.admin.llm.page.cachePrices(
      read: formatPrice(model.cacheReadPrice ?? input, currency),
      write: formatPrice(model.cacheWritePrice ?? input, currency),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final displayName = model.displayName;
    final cachePrices = _cachePrices(t);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Courier']);
    return ListTile(
      key: ValueKey('llm.model.${model.id}'),
      leading: IconButton(
        key: ValueKey('llm.model.${model.id}.default'),
        icon: Icon(model.isDefault ? Icons.star : Icons.star_border, color: model.isDefault ? _starColor : null),
        tooltip: model.isDefault ? t.base.admin.llm.page.defaultModel : t.base.admin.llm.page.makeDefault,
        onPressed: model.isDefault || busy ? null : onSetDefault,
      ),
      title: Text(displayName ?? model.apiName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (displayName != null) Text(model.apiName, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono),
          Text(_prices(t)),
          if (cachePrices != null) Text(cachePrices, style: theme.textTheme.bodySmall),
        ],
      ),
      isThreeLine: displayName != null || cachePrices != null,
      trailing: IconButton(
        key: ValueKey('llm.model.${model.id}.delete'),
        icon: const Icon(Icons.delete_outline),
        tooltip: t.base.admin.llm.page.deleteModel,
        onPressed: onDelete,
      ),
      onTap: onTap,
    );
  }
}
