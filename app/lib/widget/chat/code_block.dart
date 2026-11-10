import 'package:flutter/material.dart';

/// Monospaced text as it is, selectable and scrolling sideways instead of wrapping (e.g. JSON, a patch, a file), unless
/// [wrap] is on.
class CodeBlock extends StatelessWidget {
  final String text;

  /// Whether long lines wrap, so that it never scrolls sideways.
  final bool wrap;
  final bool italic;

  const CodeBlock({super.key, required this.text, this.wrap = false, this.italic = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const padding = EdgeInsets.all(12);
    final content = SelectableText(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Menlo', 'Courier'],
        fontStyle: italic ? FontStyle.italic : null,
        height: 1.5,
      ),
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: wrap
          ? Padding(padding: padding, child: content)
          : SingleChildScrollView(scrollDirection: Axis.horizontal, padding: padding, child: content),
    );
  }
}
