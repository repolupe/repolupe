import 'package:flutter/material.dart';

/// Monospaced text as it is, selectable and scrolling sideways instead of wrapping (e.g. JSON, a patch, a file).
class CodeBlock extends StatelessWidget {
  final String text;

  const CodeBlock({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            fontFamilyFallback: const ['Menlo', 'Courier'],
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
