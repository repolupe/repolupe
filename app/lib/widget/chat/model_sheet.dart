import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/widget/list_sheet.dart';
import 'package:app/widget/model_choices.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The models to choose for the chat, grouped by provider, or the user's model ("Default").
class ModelSheet extends StatelessWidget {
  const ModelSheet();

  static Future<void> show(BuildContext context) async {
    await ListSheet.show<void>(context, builder: (_) => const ModelSheet());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    final fallbackModel = state.fallbackModel(context.watch(meProvider.select((user) => user?.defaultModelId)));
    // The ref outlives the sheet's context, which is gone once it is closed.
    final ref = context.ref;
    return ListSheet(
      title: context.t.base.common.model,
      children: modelChoices(
        context,
        models: state.models,
        chosenModelId: state.chosenModelId,
        defaultSubtitle: fallbackModel?.displayName,
        keyPrefix: 'chat.modelSheet',
        onChosen: (modelId) async {
          Navigator.pop(context);
          await ref.redux(chatProvider).dispatchAsync(ChooseModelAction(modelId));
        },
      ),
    );
  }
}
