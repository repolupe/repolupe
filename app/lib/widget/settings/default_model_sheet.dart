import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/widget/list_sheet.dart';
import 'package:app/widget/model_choices.dart';
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
    return ListSheet.show<({UuidValue? modelId})>(
      context,
      builder: (_) => DefaultModelSheet(models: models, chosenModelId: chosenModelId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final defaultModel = models.where((m) => m.isDefault).firstOrNull;
    return ListSheet(
      title: t.base.common.model,
      hint: t.base.settings.preferences.modelDialog.description,
      children: modelChoices(
        context,
        models: models,
        chosenModelId: chosenModelId,
        defaultSubtitle: defaultModel?.displayName ?? t.flutter.settings.preferences.modelSheet.noneConfigured,
        keyPrefix: 'preferences.model',
        onChosen: (modelId) => Navigator.pop(context, (modelId: modelId)),
      ),
    );
  }
}
