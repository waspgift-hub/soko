import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Blocks non-admin users when maintenance mode is enabled in Firestore.
class MaintenanceGate extends StatefulWidget {
  final Widget child;

  const MaintenanceGate({super.key, required this.child});

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate> {
  bool _showChild = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  String _maintenanceMessage = '';

  Future<void> _check() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('maintenance')
          .get();
      if (!mounted) return;
      final enabled = doc.data()?['enabled'] == true;
      if (!enabled) return;

      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email?.toLowerCase() ?? '';
      if (email == 'admin@soko-langu.com' || email == 'admin@soko-vibe.com') {
        return;
      }

      _maintenanceMessage = (doc.data()?['message'] as String?) ??
          'App iko kwenye matengenezo. Tafadhali rudi baadaye.';
      if (mounted) setState(() => _showChild = false);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_showChild) {
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.build_circle_outlined, size: 72, color: cs.primary),
                const SizedBox(height: 24),
                Text(
                  _maintenanceMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}
