import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:app/widget/status_chip.dart';
import 'package:flutter/material.dart';

/// The sync status of a repository as a small colored chip, with the error of a failed sync as tooltip.
class SyncStatusChip extends StatelessWidget {
  final RepositoryDto repository;

  const SyncStatusChip({super.key, required this.repository});

  /// The label, color and icon of a status, like the web shows them.
  static (String, Color, IconData) info(BuildContext context, RepositorySyncStatus status) => switch (status) {
    RepositorySyncStatus.pending => (context.t.base.status.pending, Colors.grey, Icons.schedule),
    RepositorySyncStatus.syncing => (context.t.base.status.syncing, Colors.blue, Icons.sync),
    RepositorySyncStatus.ready => (context.t.base.status.ready, Colors.green, Icons.check_circle),
    RepositorySyncStatus.failed => (context.t.base.status.failed, Colors.red, Icons.error),
    RepositorySyncStatus.unknown => (context.t.flutter.repositories.statusUnknown, Colors.grey, Icons.help_outline),
  };

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = info(context, repository.syncStatus);
    final chip = StatusChip(label: label, color: color, icon: icon);
    final lastError = repository.lastError;
    return lastError == null ? chip : Tooltip(message: lastError, child: chip);
  }
}
