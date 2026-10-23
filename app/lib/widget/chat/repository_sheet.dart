import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The repositories the chat reads: chosen for a new chat, shown for an existing one, which keeps those it was
/// created with.
class RepositorySheet extends StatelessWidget {
  const RepositorySheet();

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => const RepositorySheet(),
    );
  }

  /// E.g. "All Repositories", the name of the only repository, or "3 repositories".
  static String summary(BuildContext context, ChatState state) {
    if (state.scopeAll) {
      return context.t.base.chat.allRepositories;
    }
    final ids = state.scopeIds;
    final name = ids.length == 1 ? state.repositories.where((r) => r.id == ids.first).firstOrNull?.name : null;
    return name ?? context.t.base.chat.repositoryCount(count: ids.length);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(context.t.base.repositories.title, style: theme.textTheme.titleSmall),
          ),
          if (state.chat != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                context.t.flutter.chat.repositorySheet.fixedHint,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: state.chat == null ? _choices(context, state) : _chosen(context, state),
            ),
          ),
        ],
      ),
    );
  }

  /// Checkboxes for all repositories and each one; picking one while all are chosen chooses only that one.
  List<Widget> _choices(BuildContext context, ChatState state) {
    final chat = context.redux(chatProvider);
    return [
      CheckboxListTile(
        title: Text(context.t.base.chat.allRepositories),
        value: state.allRepositories,
        onChanged: (all) => chat.dispatch(SetRepositoryScopeAction(all: all ?? false, ids: const [])),
      ),
      const Divider(),
      for (final repository in state.repositories)
        CheckboxListTile(
          title: Text(repository.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: repository.description == null ? null : Text(repository.description!, maxLines: 1, overflow: TextOverflow.ellipsis),
          value: !state.allRepositories && state.repositoryIds.contains(repository.id),
          onChanged: (selected) {
            final ids = <UuidValue>[
              if (!state.allRepositories) ...state.repositoryIds.where((id) => id != repository.id),
              if (selected ?? false) repository.id,
            ];
            chat.dispatch(SetRepositoryScopeAction(all: false, ids: ids));
          },
        ),
    ];
  }

  /// The repositories of the existing chat, without choices.
  List<Widget> _chosen(BuildContext context, ChatState state) {
    if (state.scopeAll) {
      return [ListTile(leading: const Icon(Icons.folder_copy_outlined), title: Text(context.t.base.chat.allRepositories))];
    }
    if (state.scopeIds.isEmpty) {
      return [ListTile(leading: const Icon(Icons.folder_off_outlined), title: Text(context.t.base.chat.repositoryCount(count: 0)))];
    }
    return [
      for (final id in state.scopeIds)
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          // Deleted, or no longer shared with the user.
          title: Text(
            state.repositories.where((r) => r.id == id).firstOrNull?.name ?? context.t.flutter.chat.repositorySheet.unavailable,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
  }
}
