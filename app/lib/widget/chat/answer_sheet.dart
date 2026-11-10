import 'package:flutter/material.dart';

/// A bottom sheet with details of an answer: a [title], the model that wrote it, and the [children], scrolling once
/// they don't fit.
class AnswerSheet extends StatelessWidget {
  final String title;

  /// The model that wrote the answer, `null` if unknown.
  final String? modelName;
  final List<Widget> children;

  const AnswerSheet({super.key, required this.title, required this.modelName, required this.children});

  /// Opens the sheet [builder] builds.
  static Future<void> show(BuildContext context, {required WidgetBuilder builder}) async {
    await showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: builder);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final modelName = this.modelName;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (modelName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.smart_toy_outlined, size: 16, color: muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(modelName, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
