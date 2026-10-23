import 'package:flutter/material.dart';

/// Why the last try of a dialog or sheet failed, shown inside it: a snack bar would be shown on the page below,
/// behind the modal barrier.
class InlineError extends StatelessWidget {
  final String message;

  const InlineError(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(message, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
    );
  }
}
