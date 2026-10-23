import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The models to choose for the chat, grouped by provider, or the user's model ("Default").
class ModelSheet extends StatelessWidget {
  const ModelSheet();

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => const ModelSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    final theme = Theme.of(context);
    // A model that no longer exists counts as the user's model, like on the server.
    final chosen = state.models.where((m) => m.id == state.chosenModelId).firstOrNull?.id;
    // In the order the API returns them.
    final providers = <UuidValue, List<ModelDto>>{};
    for (final model in state.models) {
      providers.putIfAbsent(model.providerId, () => []).add(model);
    }
    // The ref outlives the sheet's context, which is gone once it is closed.
    final ref = context.ref;

    Future<void> choose(UuidValue? modelId) async {
      Navigator.pop(context);
      await ref.redux(chatProvider).dispatchAsync(ChooseModelAction(modelId));
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(context.t.base.common.model, style: theme.textTheme.titleSmall),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(context.t.base.common.kDefault),
                  subtitle: state.fallbackModel == null ? null : Text(state.fallbackModel!.displayName),
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
