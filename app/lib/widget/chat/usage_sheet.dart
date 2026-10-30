import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/format.dart';
import 'package:flutter/material.dart';

/// An answer's tokens by type with their total, and its exact cost (like the web's usage dialog).
class UsageSheet extends StatelessWidget {
  final UsageDto usage;
  final CostDto? cost;

  /// The model that wrote the answer, if it still exists.
  final String? modelName;

  const UsageSheet({super.key, required this.usage, required this.cost, required this.modelName});

  static Future<void> show(BuildContext context, {required UsageDto usage, required CostDto? cost, required String? modelName}) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => UsageSheet(usage: usage, cost: cost, modelName: modelName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = context.t.base.chat.usageDialog;
    final rows = [
      (context.t.base.common.input, labels.inputHint, usage.inputTokens.toInt()),
      (labels.cacheRead, labels.cacheReadHint, usage.cacheReadTokens.toInt()),
      (labels.cacheWrite, labels.cacheWriteHint, usage.cacheWriteTokens.toInt()),
      (context.t.base.common.output, labels.outputHint, usage.outputTokens.toInt()),
    ];
    final total = rows.fold(0, (sum, row) => sum + row.$3);
    final tabular = theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final strong = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500);
    final strongTabular = tabular?.copyWith(fontWeight: FontWeight.w500);
    final cost = this.cost;
    final modelName = this.modelName;
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('chat.usage'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(labels.title, style: theme.textTheme.titleMedium),
            if (modelName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.smart_toy_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(modelName, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            _Row(
              label: Text(labels.type, style: theme.textTheme.labelMedium),
              value: Text(labels.tokens, style: theme.textTheme.labelMedium),
            ),
            for (final (label, hint, tokens) in rows)
              _Row(
                label: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                value: Text(formatCount(tokens), style: tabular),
              ),
            _Row(
              label: Text(labels.total, style: strong),
              value: Text(formatCount(total), style: strongTabular),
            ),
            if (cost != null)
              _Row(
                label: Text(labels.cost, style: strong),
                value: Text(formatExactCost(cost.amount, cost.currency), style: strongTabular),
                divider: false,
              ),
          ],
        ),
      ),
    );
  }
}

/// A row of the table, with the value right-aligned and a divider below.
class _Row extends StatelessWidget {
  final Widget label;
  final Widget value;
  final bool divider;

  const _Row({required this.label, required this.value, this.divider = true});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? Border(bottom: BorderSide(color: Theme.of(context).dividerColor)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: label),
            const SizedBox(width: 16),
            value,
          ],
        ),
      ),
    );
  }
}
