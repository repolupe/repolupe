import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// The models to choose as the user's own, grouped by provider, or the default model ("Default").
class DefaultModelSheet extends StatelessWidget {
  final List<ModelDto> models;

  /// The user's model, `null` for the default.
  final UuidValue? chosenModelId;

  const DefaultModelSheet({super.key, required this.models, required this.chosenModelId});

  /// Returns the chosen model (`modelId` `null` for the default), or `null` if the sheet was dismissed.
  static Future<({UuidValue? modelId})?> show(
    BuildContext context, {
    required List<ModelDto> models,
    required UuidValue? chosenModelId,
  }) {
    return showModalBottomSheet<({UuidValue? modelId})>(
      context: context,
      showDragHandle: true,
      builder: (_) => DefaultModelSheet(models: models, chosenModelId: chosenModelId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    // A model that no longer exists counts as the default, like on the server.
    final chosen = models.where((m) => m.id == chosenModelId).firstOrNull?.id;
    final defaultModel = models.where((m) => m.isDefault).firstOrNull;
    // In the order the API returns them.
    final providers = <UuidValue, List<ModelDto>>{};
    for (final model in models) {
      providers.putIfAbsent(model.providerId, () => []).add(model);
    }

    void choose(UuidValue? modelId) {
      Navigator.pop(context, (modelId: modelId));
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(t.base.common.model, style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              t.base.settings.preferences.modelDialog.description,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  key: const ValueKey('preferences.model.default'),
                  title: Text(t.base.common.kDefault),
                  subtitle: Text(defaultModel?.displayName ?? t.flutter.settings.preferences.modelSheet.noneConfigured),
                  selected: chosen == null,
                  trailing: chosen == null ? const Icon(Icons.check) : null,
                  onTap: () => choose(null),
                ),
                for (final models in providers.values) ...[
                  // The provider headings only help to tell several providers apart.
                  if (providers.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        models.first.providerName,
                        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  for (final model in models)
                    ListTile(
                      key: ValueKey('preferences.model.${model.id}'),
                      title: Text(model.displayName),
                      selected: model.id == chosen,
                      trailing: model.id == chosen ? const Icon(Icons.check) : null,
                      onTap: () => choose(model.id),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
