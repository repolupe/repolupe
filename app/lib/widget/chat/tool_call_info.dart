import 'package:app/service/chat_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/tool_call.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Whether a tool call is running, completed or failed.
class ToolCallStatusIcon extends StatelessWidget {
  final ToolCallStatus status;

  const ToolCallStatusIcon({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (status) {
      ToolCallStatus.running => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      ToolCallStatus.completed => Icon(Icons.check, size: 16, color: colors.primary),
      ToolCallStatus.failed => Icon(Icons.error_outline, size: 16, color: colors.error),
      ToolCallStatus.unknown => Icon(Icons.help_outline, size: 16, color: colors.onSurfaceVariant),
    };
  }
}

/// The repository of a tool call and the path it refers to, e.g. `docs › guide/setup.md`.
class ToolCallLocation extends StatelessWidget {
  final ToolCallSummaryDto toolCall;

  /// The path, without one only the repository.
  final String? path;

  const ToolCallLocation({super.key, required this.toolCall, required this.path});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repositories = context.watch(chatProvider.select((s) => s.repositories));
    final repository = repositories.where((r) => r.id == toolCall.repositoryId).firstOrNull?.name ?? toolCall.repositoryName;
    final text = [?repository, if (path case final path? when path.isNotEmpty) path].join(' › ');
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant));
  }
}
