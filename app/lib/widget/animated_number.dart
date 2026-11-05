import 'package:flutter/widgets.dart';

/// How long counting to a new value takes.
const _duration = Duration(milliseconds: 600);

/// A number that counts to each new value instead of jumping to it (like the web's `AnimatedNumber`). The value it
/// starts with is shown at once, and so is every change if animations are disabled. Once there, it is exactly [value].
class AnimatedNumber extends StatelessWidget {
  final double value;

  /// Gets the numbers in between too, not only [value].
  final String Function(double value) format;
  final TextStyle? style;

  const AnimatedNumber({super.key, required this.value, required this.format, this.style});

  @override
  Widget build(BuildContext context) {
    // Without a begin, it starts at the end; a new end is counted to from wherever it is, also while counting.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : _duration,
      // fast at first, settling on the value
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Text(format(value), style: style),
    );
  }
}
