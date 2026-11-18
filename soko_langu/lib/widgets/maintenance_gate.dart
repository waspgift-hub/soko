import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../extensions/context_tr.dart';

/// Blocks non-admin users when maintenance mode is enabled in Firestore.
///
/// The child stays mounted behind the maintenance card (it is never swapped
/// out for a different subtree). Replacing the child with a `Scaffold` in
/// `build` unmounts the entire router — including any open dialog — which
/// triggered `_dependents.isEmpty` / `child._parent == this` assertions and
/// discarded navigation state.
class MaintenanceGate extends StatefulWidget {
  final Widget child;

  const MaintenanceGate({super.key, required this.child});

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate> {
  bool _blocked = false;
  String _maintenanceMessage = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('maintenance')
          .get();
      if (!mounted) return;
      final enabled = doc.data()?['enabled'] == true;
      if (!enabled) {
        // Recovery path for the retry button: once the window closes the
        // overlay must come down without a restart.
        if (_blocked) setState(() => _blocked = false);
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email?.toLowerCase() ?? '';
      if (email == 'admin@sokovibe.co.tz' ||
          email == 'admin@soko-langu.com' ||
          email == 'admin@soko-vibe.com') {
        if (_blocked) setState(() => _blocked = false);
        return;
      }

      if (!mounted) return;
      setState(() {
        _maintenanceMessage =
            (doc.data()?['message'] as String?) ??
            context.tr(
              'maintenance_underway',
              'App iko kwenye matengenezo. Tafadhali rudi baadaye.',
            );
        _blocked = true;
      });
    } catch (_) {
      // A failed check must never block the app.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_blocked) _MaintenanceScreen(message: _maintenanceMessage, onRetry: _check),
      ],
    );
  }
}

class _MaintenanceScreen extends StatefulWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _MaintenanceScreen({required this.message, required this.onRetry});

  @override
  State<_MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<_MaintenanceScreen> {
  bool _checking = false;

  Future<void> _retry() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.build_circle_outlined, size: 56, color: cs.primary),
                ),
                const SizedBox(height: 24),
                Text(
                  'Soko Vibe',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                // The gate only checked once at startup, so a finished
                // maintenance window left the overlay up until a force-close.
                OutlinedButton.icon(
                  onPressed: _checking ? null : _retry,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(context.tr('try_again', 'Jaribu tena')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
