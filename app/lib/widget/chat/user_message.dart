import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:flutter/material.dart';

/// A message the user sent, on the right.
class UserMessage extends StatelessWidget {
  final MessageDto message;

  const UserMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.85),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SelectableText(
            message.content,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
      ),
    );
  }
}
