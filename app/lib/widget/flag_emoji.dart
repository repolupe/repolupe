import 'package:flutter/material.dart';

/// A flag emoji in front of a list tile's title. Without one, the empty box keeps the titles aligned.
class FlagEmoji extends StatelessWidget {
  final String? emoji;

  const FlagEmoji(this.emoji, {super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 24, child: Text(emoji ?? '', style: Theme.of(context).textTheme.titleLarge));
  }
}
