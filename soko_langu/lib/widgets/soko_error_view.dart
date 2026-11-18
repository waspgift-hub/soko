import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Replacement for Flutter's red error screen.
///
/// A build/layout error used to take over the whole frame with a red box, which
/// reads as "the app is broken" even when it is one bad tile. This renders a
/// calm, self-contained card instead: no `Theme`, `MediaQuery`, `Directionality`
/// or `Localizations` lookups, because those are exactly the inherited widgets
/// that may be missing when the error happens. The original exception is still
/// reported through [FlutterError.onError] (Crashlytics) before this is built.
class SokoErrorView extends StatelessWidget {
  final String? details;

  const SokoErrorView({super.key, this.details});

  static const Color _canvas = Color(0xFF0E1512);
  static const Color _surface = Color(0xFF17211D);
  static const Color _accent = Color(0xFF52D08B);
  static const Color _muted = Color(0xFFA7B5AE);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: _canvas,
        // The builder runs wherever the failing widget sat. That slot is
        // sometimes unbounded (inside a Column in a scroll view), where a
        // scrollable card would itself throw — check first instead of assuming
        // a full-screen parent.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final card = _buildCard();
            if (!constraints.hasBoundedHeight) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: card,
              );
            }
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: card,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi_tethering_error_rounded,
              color: _accent,
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Sehemu hii haikupakia vizuri',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'This section could not load. Go back or try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
          if (kDebugMode && details != null && details!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                details!,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFFB4AB),
                  fontSize: 10,
                  height: 1.35,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
