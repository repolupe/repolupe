import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/widget/chat/scope_choices.dart';
import 'package:app/widget/list_sheet.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The repositories a new chat reads, chosen among those the user can read (see [ChatState.repositories]).
class RepositorySheet extends StatelessWidget {
  const RepositorySheet();

  static Future<void> show(BuildContext context) async {
    await ListSheet.show<void>(context, builder: (_) => const RepositorySheet());
  }

  /// E.g. "All Repositories", the name of the only repository, or "3 repositories".
  static String summary(BuildContext context, ChatState state) {
    if (state.allRepositories) {
      return context.t.base.chat.allRepositories;
    }
    final ids = state.repositoryIds;
    final name = ids.length == 1 ? state.repositories.where((r) => r.id == ids.first).firstOrNull?.name : null;
    return name ?? context.t.base.chat.repositoryCount(count: ids.length);
  }

  /// A folder, crossed out while no repository is chosen.
  static IconData icon(ChatState state) => !state.allRepositories && state.repositoryIds.isEmpty ? Icons.folder_off_outlined : Icons.folder_outlined;

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    final chat = context.redux(chatProvider);
    return ListSheet(
      title: context.t.base.repositories.title,
      children: scopeChoices(
        allTitle: context.t.base.chat.allRepositories,
        all: state.allRepositories,
        ids: state.repositoryIds,
        items: [
          for (final repository in state.repositories) (id: repository.id, title: repository.name, subtitle: repository.description),
        ],
        onChanged: (all, ids) => chat.dispatch(SetRepositoryScopeAction(all: all, ids: ids)),
      ),
    );
  }
}
