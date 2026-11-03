import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// A "Default" tile with [defaultSubtitle] (e.g. the model it resolves to), then the [models] grouped by provider, the
/// [chosenModelId] checked. A chosen model that no longer exists counts as the default, like on the server.
/// The tiles' keys are `<keyPrefix>.default` and `<keyPrefix>.<model id>`.
List<Widget> modelChoices(
  BuildContext context, {
  required List<ModelDto> models,
  required UuidValue? chosenModelId,
  required String? defaultSubtitle,
  required String keyPrefix,
  required void Function(UuidValue? modelId) onChosen,
}) {
  final theme = Theme.of(context);
  final chosen = models.where((m) => m.id == chosenModelId).firstOrNull?.id;
  // In the order the API returns them.
  final providers = <UuidValue, List<ModelDto>>{};
  for (final model in models) {
    providers.putIfAbsent(model.providerId, () => []).add(model);
  }
  return [
    ListTile(
      key: ValueKey('$keyPrefix.default'),
      title: Text(context.t.base.common.kDefault),
      subtitle: defaultSubtitle == null ? null : Text(defaultSubtitle),
      selected: chosen == null,
      trailing: chosen == null ? const Icon(Icons.check) : null,
      onTap: () => onChosen(null),
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
          key: ValueKey('$keyPrefix.${model.id}'),
          title: Text(model.displayName),
          selected: model.id == chosen,
          trailing: model.id == chosen ? const Icon(Icons.check) : null,
          onTap: () => onChosen(model.id),
        ),
    ],
  ];
}
