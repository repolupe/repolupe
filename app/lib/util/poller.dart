import 'dart:async';

/// Calls [poll] every [interval] while [needed] says so, e.g. to follow a sync quietly. Call [update] after each
/// load (and whenever what [needed] looks at changes), [dispose] with the widget.
class Poller {
  final Duration interval;
  final bool Function() needed;
  final Future<void> Function() poll;
  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;

  Poller({required this.interval, required this.needed, required this.poll});

  /// Schedules the next poll if one is [needed], else stops polling. A scheduled poll is scheduled again.
  void update() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || _polling || !needed()) {
      return;
    }
    _timer = Timer(interval, _tick);
  }

  Future<void> _tick() async {
    _timer = null;
    _polling = true;
    try {
      await poll();
    } finally {
      _polling = false;
    }
    update();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
