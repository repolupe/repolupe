import 'package:flutter/material.dart';

/// A bottom sheet with a [title], a [hint] below it, and the [children] in a list that scrolls once they don't fit.
class ListSheet extends StatelessWidget {
  final String title;

  /// E.g. what the items are for, or why they can't be changed.
  final String? hint;
  final List<Widget> children;

  const ListSheet({super.key, required this.title, this.hint, required this.children});

  /// Opens the sheet [builder] builds, returning what it is closed with.
  static Future<T?> show<T>(BuildContext context, {required WidgetBuilder builder}) {
    return showModalBottomSheet<T>(context: context, showDragHandle: true, builder: builder);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = this.hint;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, hint == null ? 8 : 4),
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          Flexible(
            child: ListView(shrinkWrap: true, children: children),
          ),
        ],
      ),
    );
  }
}
