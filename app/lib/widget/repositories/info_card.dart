import 'package:flutter/material.dart';

/// A card of a repository's page: a titled section of [InfoRow]s (or other widgets) with optional actions below,
/// and an optional [trailing] widget next to the title (e.g. a menu).
class InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final List<Widget> children;
  final List<Widget> actions;

  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    required this.children,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                ?trailing,
              ],
            ),
          ),
          ...children,
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: actions),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A labelled value in an [InfoCard]: the label above the [value] text (or [child]), with an optional [tooltip]
/// (e.g. the exact time behind a relative one).
class InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;
  final String? tooltip;
  final bool monospace;

  const InfoRow({super.key, required this.label, this.value, this.child, this.tooltip, this.monospace = false})
    : assert(value != null || child != null, 'value or child');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content =
        child ??
        Text(
          value!,
          style: monospace ? theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Courier']) : null,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          if (tooltip != null) Tooltip(message: tooltip!, child: content) else content,
        ],
      ),
    );
  }
}
