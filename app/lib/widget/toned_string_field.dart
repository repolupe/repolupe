import 'package:flutter/material.dart';
import 'package:moform/moform.dart';

/// A single-line text field in a box a shade darker than the page's background, like the message input,
/// with [actions] (usually [IconButton]s) at its end.
class TonedStringField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? hint;
  final TextInputAction? textInputAction;
  final List<Widget> actions;

  const TonedStringField({
    super.key,
    required this.value,
    required this.onChanged,
    this.onSubmitted,
    this.hint,
    this.textInputAction,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // The buttons are as far from the edges as in the message input.
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: StringField(
              value: value,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: textInputAction,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                // As far from the edge as the message input's text, as tall as the buttons.
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
