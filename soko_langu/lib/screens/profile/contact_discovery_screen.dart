import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/user_service.dart';
import '../../widgets/social/follow_button.dart';

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
  bool _loadingMatches = false;
  List<UserProfile> _matches = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _extractPhone(Map<String, dynamic>? data) {
    if (data == null) return null;
    // Try every key the app has ever used for a phone number, then fall back to
    // scanning the document for any phone-like string so a renamed field does
    // not silently break discovery.
    const keys = [
      'phone',
      'phoneNumber',
      'phoneNumberE164',
      'phoneE164',
      'mobile',
      'mobileNumber',
      'contactPhone',
      'userPhone',
    ];
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    // paymentNumbers is a map of label -> number; use its first value.
    final pn = data['paymentNumbers'];
    if (pn is Map && pn.isNotEmpty) {
      final first = pn.values.first;
      if (first is String && first.trim().isNotEmpty) return first.trim();
    }
    for (final v in data.values) {
      if (v is String) {
        final digits = v.replaceAll(RegExp(r'\D'), '');
        if (digits.length >= 9 && digits.length <= 15) return v.trim();
      }
    }
    return null;
  }

  Future<void> _load() async {
    try {
      final enabled = await _service.isOptedIn();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
      if (enabled) unawaited(_loadMatches());
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
            phone = _extractPhone(data);
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
        await _loadMatches();
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

  Future<void> _loadMatches() async {
    if (!mounted) return;
    setState(() => _loadingMatches = true);
    try {
      final granted = await FlutterContacts.requestPermission();
      if (!granted) {
        if (mounted) setState(() => _loadingMatches = false);
        return;
      }
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final phones = <String>{};
      for (final c in contacts) {
        for (final p in c.phones) {
          final n = p.number.trim();
          if (n.isNotEmpty) phones.add(n);
        }
      }
      if (phones.isEmpty) {
        if (mounted) setState(() => _loadingMatches = false);
        return;
      }
      final uids = await _service.matchContacts(phones.toList());
      final profiles = <UserProfile>[];
      for (final uid in uids) {
        try {
          final p = await UserService().getProfile(uid);
          if (p != null) profiles.add(p);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _matches = profiles;
          _loadingMatches = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMatches = false);
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
                if (_enabled) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    context.tr('people_you_may_know', 'People You May Know'),
                    style: AppTypography.bodyMedium(cs.onSurface).copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  if (_loadingMatches)
                    const Center(child: CircularProgressIndicator())
                  else if (_matches.isEmpty)
                    Text(
                      context.tr('no_matches_found', 'No matches yet'),
                      style: AppTypography.bodySmall(cs.onSurfaceVariant),
                    )
                  else
                    SizedBox(
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _matches.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final u = _matches[i];
                          return Column(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundImage: u.profileImage.isNotEmpty
                                    ? NetworkImage(u.profileImage)
                                    : null,
                                child: u.profileImage.isEmpty
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  u.displayName.isNotEmpty ? u.displayName : u.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              FollowButton(targetUserId: u.uid, size: FollowButtonSize.small),
                            ],
                          );
                        },
                      ),
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
