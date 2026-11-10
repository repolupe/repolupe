import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/format.dart';
import 'package:flutter/material.dart';

extension UsageTotal on UsageDto {
  /// Input (including the cache) and output.
  int get totalTokens => (inputTokens + cacheReadTokens + cacheWriteTokens + outputTokens).toInt();
}

/// An answer's tokens by type with their total, and its exact cost by type at the prices (like the web's usage
/// dialog).
class UsageSheet extends StatelessWidget {
  final UsageDto usage;
  final CostDto? cost;

  /// The model that wrote the answer, `null` if unknown.
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
    final cost = this.cost;
    final prices = cost?.prices;
    final rows = [
      (context.t.base.common.input, labels.inputHint, usage.inputTokens.toInt(), prices?.input),
      (labels.cacheRead, labels.cacheReadHint, usage.cacheReadTokens.toInt(), prices?.cacheRead),
      (labels.cacheWrite, labels.cacheWriteHint, usage.cacheWriteTokens.toInt(), prices?.cacheWrite),
      (context.t.base.common.output, labels.outputHint, usage.outputTokens.toInt(), prices?.output),
    ];
    final total = usage.totalTokens;
    final tabular = theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final strong = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500);
    final strongTabular = tabular?.copyWith(fontWeight: FontWeight.w500);
    final hintStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
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
              cost: prices != null ? Text(labels.cost, style: theme.textTheme.labelMedium) : null,
            ),
            for (final (label, hint, tokens, price) in rows)
              _Row(
                label: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    Text(hint, style: hintStyle),
                  ],
                ),
                value: Text(formatCount(tokens), style: tabular),
                cost: cost != null && price != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatExactCost(tokenCost(tokens, price), cost.currency), style: tabular),
                          Text(
                            labels.pricePerMillion(price: formatPrice(price, cost.currency)),
                            style: hintStyle,
                            textAlign: TextAlign.end,
                          ),
                        ],
                      )
                    : null,
              ),
            _Row(
              label: Text(labels.total, style: strong),
              value: Text(formatCount(total), style: strongTabular),
              cost: cost != null && prices != null ? Text(formatExactCost(cost.amount, cost.currency), style: strongTabular) : null,
              divider: prices == null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of the table, with the values right-aligned and a divider below.
class _Row extends StatelessWidget {
  final Widget label;
  final Widget value;

  /// A third column, only in tables with prices. Then the columns have fixed shares of the width, so they line up.
  final Widget? cost;
  final bool divider;

  const _Row({required this.label, required this.value, this.cost, this.divider = true});

  @override
  Widget build(BuildContext context) {
    final cost = this.cost;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? Border(bottom: BorderSide(color: Theme.of(context).dividerColor)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: cost == null
            ? Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 16),
                  value,
                ],
              )
            : Row(
                // the cost has the price below it, like the label its hint
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: label),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: Align(alignment: Alignment.topRight, child: value),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 4,
                    child: Align(alignment: Alignment.topRight, child: cost),
                  ),
                ],
              ),
      ),
    );
  }
}
