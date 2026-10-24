import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../services/user_service.dart';
import '../../services/seller_verification_service.dart';
import '../../api_config.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../theme/design_tokens.dart';

/// Admin Privacy & Verification settings screen.
///
/// Allows the account owner to:
/// * Toggle their account between public and private
/// * Claim / change their username (unique, server-validated)
/// * See their current Blue Tick / verification status
///
/// Everything here is written to server-owned documents — the client never
/// writes trust or verification state directly.
class AdminPrivacyScreen extends StatefulWidget {
  const AdminPrivacyScreen({super.key});

  @override
  State<AdminPrivacyScreen> createState() => _AdminPrivacyScreenState();
}

class _AdminPrivacyScreenState extends State<AdminPrivacyScreen> {
  final UserService _userService = UserService();
  final SellerVerificationService _verificationService =
      SellerVerificationService();

  bool _isPrivate = false;
  bool _isLoading = true;
  String? _username;
  String? _usernameError;
  final TextEditingController _usernameController = TextEditingController();
  bool _isSavingUsername = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final profile = await _userService.getProfile(user.uid);
      if (!mounted) return;

      final verification = await _verificationService.resolve(user.uid);
      if (!mounted) return;

      // Read privacy setting from the server-owned users/{uid} doc
      final snap =
          await _userService.getPrivateSettings(user.uid);
      if (!mounted) return;

      setState(() {
        _username = profile.username.isNotEmpty ? profile.username : '';
        _usernameController.text = _username ?? '';
        _isPrivate = snap.data()?['visibility']?['isPrivate'] == true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  /// Toggle the account between public and private.
  /// Writes to the server-owned users/{uid} doc via the API.
  Future<void> _togglePrivate(bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final token = await user.getIdToken();
      final res = await http.put(
        Uri.parse(ApiConfig.v1('/users/me/privacy')),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'visibility': {'isPrivate': value}}),
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        setState(() => _isPrivate = value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? context.tr('account_private')
                  : context.tr('account_public'),
            ),
          ),
        );
      } else {
        setState(() => _isPrivate = !value); // Revert
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('failed_to_update_privacy'))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPrivate = !value); // Revert
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Claim or change the username.
  Future<void> _saveUsername() async {
    final newName = _usernameController.text.trim();
    if (newName.isEmpty) {
      setState(() => _usernameError = context.tr('username_required'));
      return;
    }

    setState(() => _isSavingUsername = true);
    try {
      await _userService.claimUsername(newName);
      if (!mounted) return;

      setState(() {
        _username = newName;
        _usernameError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('username_updated'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _usernameError = e.toString());
    } finally {
      if (mounted) setState(() => _isSavingUsername = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ads_config_title')), // placeholder — will fix
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppInsets.s4),
        children: [
          _SectionHeader(title: context.tr('privacy_settings')),

          const SizedBox(height: AppInsets.s2),

          // Public / Private toggle
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppInsets.s4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('private_account'),
                          style: TextStyle(
                            fontSize: AppFontSize.md,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppInsets.s1),
                        Text(
                          context.tr('private_account_desc'),
                          style: TextStyle(
                            fontSize: AppFontSize.xs,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: _isPrivate,
                      onChanged: _isLoading ? null : _togglePrivate,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: AppInsets.s6),

          // Username claim
          _SectionHeader(title: context.tr('username')),

          Padding(
            padding: const EdgeInsets.all(AppInsets.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: context.tr('username'),
                    hintText: context.tr('username_hint'),
                    errorText: _usernameError,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  onChanged: (v) => setState(() => _username = v),
                ),
                const SizedBox(height: AppInsets.s2),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSavingUsername ? null : _saveUsername,
                    child: _isSavingUsername
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(context.tr('save_username')),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppInsets.s6),

          // Blue Tick status (read-only)
          _SectionHeader(title: context.tr('blue_tick')),

          Padding(
            padding: const EdgeInsets.all(AppInsets.s4),
            child: Row(
              children: [
                FutureBuilder<SellerVerification>(
                  future: _verificationService.resolve(
                    FirebaseAuth.instance.currentUser!.uid,
                  ),
                  builder: (context, snap) {
                    final v = snap.data;
                    final isBlueTick = v?.isBlueTickActive == true;
                    return Row(
                      children: [
                        Icon(
                          Icons.verified,
                          size: 20,
                          color: isBlueTick
                              ? cs.brandSuccess
                              : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppInsets.s2),
                        Text(
                          isBlueTick
                              ? context.tr('blue_tick_active')
                              : context.tr('blue_tick_not_active'),
                          style: TextStyle(
                            fontSize: AppFontSize.md,
                            color: isBlueTick
                                ? cs.brandSuccess
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    context.pushNamed('admin_kyc');
                  },
                  child: Text(context.tr('kyc_management')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _SectionHeader({required String title}) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppInsets.s4,
        top: AppInsets.s4,
        bottom: AppInsets.s2,
        right: AppInsets.s4,
      ),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: AppFontSize.xs,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}