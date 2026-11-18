import 'dart:async';

import 'package:flutter/material.dart';

/// A self-updating countdown that repaints only its own subtree.
///
/// Screens used to run a 1 Hz `setState` on the whole page to move a countdown
/// by one second. That rebuilt product cards, banners and lists every second and
/// was a major source of jank. Wrapping the label keeps the tick local.
class LiveCountdown extends StatefulWidget {
  const LiveCountdown({
    super.key,
    required this.endTime,
    required this.builder,
    this.onExpired,
  });

  final DateTime endTime;

  /// Builds the visible label from the remaining time. [remaining] is clamped to
  /// zero so a formatter never sees negative values.
  final Widget Function(BuildContext context, Duration remaining) builder;

  /// Fires once when the countdown reaches zero, so the parent can refresh data.
  final VoidCallback? onExpired;

  @override
  State<LiveCountdown> createState() => _LiveCountdownState();
}

class _LiveCountdownState extends State<LiveCountdown> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    _remaining = _clamp(widget.endTime.difference(DateTime.now()));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant LiveCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endTime != widget.endTime) {
      _notified = false;
      _remaining = _clamp(widget.endTime.difference(DateTime.now()));
    }
  }

  Duration _clamp(Duration value) => value.isNegative ? Duration.zero : value;

  void _tick() {
    final next = _clamp(widget.endTime.difference(DateTime.now()));
    if (next == Duration.zero && !_notified) {
      _notified = true;
      widget.onExpired?.call();
    }
    if (next == _remaining) return;
    if (mounted) setState(() => _remaining = next);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _remaining);
}
