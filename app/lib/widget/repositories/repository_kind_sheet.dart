import 'package:app/gen/strings.g.dart';
import 'package:flutter/material.dart';

/// Whether a repository is synced from a remote or only exists on the server.
enum RepositoryKind { remote, local }

/// Chooses the kind of a new repository.
class RepositoryKindSheet extends StatelessWidget {
  const RepositoryKindSheet();

  /// Returns the chosen kind, `null` if the sheet was dismissed.
  static Future<RepositoryKind?> show(BuildContext context) async {
    return showModalBottomSheet<RepositoryKind>(
      context: context,
      showDragHandle: true,
      builder: (_) => const RepositoryKindSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(context.t.base.repositories.newRepository, style: theme.textTheme.titleSmall),
          ),
          ListTile(
            key: const ValueKey('repositories.kind.remote'),
            leading: const Icon(Icons.cloud_sync_outlined),
            title: Text(context.t.base.repositories.remote),
            subtitle: Text(context.t.base.repositories.kindDialog.remoteDescription),
            onTap: () => Navigator.pop(context, RepositoryKind.remote),
          ),
          ListTile(
            key: const ValueKey('repositories.kind.local'),
            leading: const Icon(Icons.dns_outlined),
            title: Text(context.t.base.repositories.local),
            subtitle: Text(context.t.base.repositories.kindDialog.localDescription),
            onTap: () => Navigator.pop(context, RepositoryKind.local),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
