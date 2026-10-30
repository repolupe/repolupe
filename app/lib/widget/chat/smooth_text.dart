import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Characters per second at least, so the rest of a batch does not trail off.
const _minSpeed = 120;

/// The text not shown yet is revealed at a rate that would show it within this long (ms), so it keeps up with the stream.
const _catchUpMs = 250;

/// Builds [text], revealing what is appended to it gradually instead of in the batches it arrives in (like the web's
/// `useSmoothText`). The text it starts with, and any change other than an append, is shown at once.
class SmoothText extends StatefulWidget {
  final String text;

  /// [revealing] is whether part of the text is not shown yet.
  final Widget Function(BuildContext context, String text, bool revealing) builder;

  const SmoothText({super.key, required this.text, required this.builder});

  @override
  State<SmoothText> createState() => _SmoothTextState();
}

class _SmoothTextState extends State<SmoothText> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late int _shown = widget.text.length;

  /// Fractional, [_shown] is its floor.
  late double _position = _shown.toDouble();
  Duration _last = Duration.zero;

  @override
  void didUpdateWidget(SmoothText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = widget.text;
    final appended = text.startsWith(oldWidget.text.substring(0, _shown));
    if (!appended || MediaQuery.disableAnimationsOf(context)) {
      _ticker.stop();
      _position = text.length.toDouble();
      _shown = text.length;
    } else if (!_ticker.isActive && _shown < text.length) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final ms = (elapsed - _last).inMicroseconds / 1000;
    _last = elapsed;
    final length = widget.text.length;
    final speed = max(_minSpeed / 1000, (length - _position) / _catchUpMs);
    _position = min(length.toDouble(), _position + speed * ms);
    setState(() => _shown = _position.floor());
    if (_position >= length) {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    var end = _shown;
    // not between the halves of a surrogate pair
    if (end > 0 && end < text.length) {
      final code = text.codeUnitAt(end - 1);
      if (code >= 0xd800 && code <= 0xdbff) {
        end++;
      }
    }
    return widget.builder(context, text.substring(0, end), end < text.length);
  }
}
