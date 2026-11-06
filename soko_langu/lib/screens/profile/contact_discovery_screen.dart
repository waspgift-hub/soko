import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../services/contact_discovery_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../widgets/animations/soko_animated_illustration.dart';

/// Opt-in contact discovery. Never uploads an address book.
///
/// Enabling discovery only registers a server-side HMAC of the signed-in
/// user's own verified phone so friends who already have that number can
/// find the public profile. Username search remains the default path.
class ContactDiscoveryScreen extends StatefulWidget {
  const ContactDiscoveryScreen({super.key});

  @override
  State<ContactDiscoveryScreen> createState() => _ContactDiscoveryScreenState();
}

class _ContactDiscoveryScreenState extends State<ContactDiscoveryScreen> {
  final ContactDiscoveryService _service = ContactDiscoveryService();
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await _service.isOptedIn();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (value) {
        final status = await Permission.contacts.request();
        if (!status.isGranted) {
          setState(() {
            _error = context.tr('contact_permission_denied');
            _saving = false;
          });
          return;
        }
        String? phone = FirebaseAuth.instance.currentUser?.phoneNumber;
        if (phone == null || phone.isEmpty) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
            final data = snap.data();
            phone = (data?['phone'] ?? data?['phoneNumber'] ?? data?['phoneNumberE164'])?.toString();
          }
        }
        if (phone == null || phone.isEmpty) {
          setState(() {
            _error = context.tr('contact_discovery_need_phone');
            _saving = false;
          });
          return;
        }
        await _service.optIn(ownPhone: phone);
      } else {
        await _service.optOut();
      }
      if (!mounted) return;
      setState(() {
        _enabled = value;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.tr('contact_discovery_unavailable');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('contact_discovery_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.s5),
              children: [
                const Center(
                  child: SokoAnimatedIllustration(
                    SokoIllustration.emptySearch,
                    size: 120,
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  context.tr('contact_discovery_body'),
                  style: AppTypography.bodyMedium(cs.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.s5),
                SwitchListTile(
                  value: _enabled,
                  onChanged: _saving ? null : _setEnabled,
                  title: Text(context.tr('contact_discovery_opt_in')),
                  subtitle: Text(
                    context.tr('contact_discovery_opt_in_sub'),
                    style: AppTypography.bodySmall(cs.onSurfaceVariant),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.s3),
                  Text(
                    _error!,
                    style: AppTypography.bodySmall(cs.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.s5),
                FilledButton.icon(
                  onPressed: () => context.push(AppRoutes.userSearch),
                  icon: const Icon(Icons.search),
                  label: Text(context.tr('contact_discovery_search_instead')),
                ),
              ],
            ),
    );
  }
}
