import 'package:flutter/material.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../order/my_orders_screen.dart';
import '../chat/chats_list_screen.dart';
import '../media/media_player_screen.dart';
import 'settings_screen.dart';
import 'wishlist_screen.dart';
import 'my_ads_screen.dart';
import 'edit_profile_screen.dart';
import 'seller_dashboard_screen.dart';
import '../admin/admin_dashboard_screen.dart';
import '../../services/user_service.dart';
import '../../services/auth_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/verified_badge.dart';
import '../../main.dart';
import '../../widgets/tier_badge.dart';
import '../../widgets/ad_banner.dart';
import 'premium_upgrade_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ImagePicker _picker = ImagePicker();
  final UserService _userService = UserService();
  UserProfile? _profile;
  String? _localImagePath;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    var profile = await _userService.getProfile(user.uid);
    if (profile != null && profile.email == 'admin@soko-langu.com') {
      if (profile.accountTier != 'silver') {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'accountTier': 'silver',
          'isPremium': true,
          'premiumUntil': null,
        }, SetOptions(merge: true));
        profile = await _userService.getProfile(user.uid);
      }
    }
    if (mounted) {
      setState(() => _profile = profile);
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() => _localImagePath = image.path);
        final url = await _userService.uploadProfileImage(image.path);
        await _userService.updateProfileImage(url);
        await _loadProfile();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.tr('photo_updated'))));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _refreshProfile() async {
    _localImagePath = null;
    await _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final imageUrl = _localImagePath ?? _profile?.profileImage;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.tr('profile')),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.green,
                  backgroundImage: imageUrl != null
                      ? (imageUrl.startsWith('http')
                            ? NetworkImage(imageUrl) as ImageProvider
                            : FileImage(File(imageUrl)))
                      : null,
                  child: imageUrl == null
                      ? Text(
                          _profile?.displayName.isNotEmpty == true
                              ? _profile!.displayName[0].toUpperCase()
                              : user?.displayName != null
                              ? user!.displayName![0].toUpperCase()
                              : user?.email != null
                              ? user!.email![0].toUpperCase()
                              : "U",
                          style: const TextStyle(
                            fontSize: 40,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _profile?.displayName.isNotEmpty == true
                      ? _profile!.displayName
                      : user?.displayName ?? context.tr('no_name'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                VerifiedBadge(tier: _profile?.accountTier),
              ],
            ),
            if (_profile?.bio.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                _profile!.bio,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.54),
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              user?.email ?? context.tr('no_email'),
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.54),
                fontSize: 16,
              ),
            ),
            if (_profile?.phone.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.phone, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _profile!.phone,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.54),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
            if (_profile?.location.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _profile!.location,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.54),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            _buildTierSection(),
            const SizedBox(height: 20),
            _button(
              icon: Icons.edit,
              text: context.tr('edit_profile'),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );
                _refreshProfile();
              },
            ),
            const SizedBox(height: 15),
            // ❤️ WISHLIST
            _button(
              icon: Icons.favorite,
              text: context.tr('wishlist'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WishlistScreen()),
                );
              },
            ),
            const SizedBox(height: 15),
            // 📦 ORDERS
            _button(
              icon: Icons.receipt_long,
              text: context.tr('my_orders'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
                );
              },
            ),
            const SizedBox(height: 15),
            // ❤️ MY ADS
            _button(
              icon: Icons.shopping_bag,
              text: context.tr('my_ads'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyAdsScreen()),
                );
              },
            ),
            const SizedBox(height: 15),
            // 📊 DASHBOARD
            _button(
              icon: Icons.dashboard,
              text: context.tr('dashboard'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SellerDashboardScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 15),
            // 💬 CHATS
            _button(
              icon: Icons.chat_bubble,
              text: context.tr('chats'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatsListScreen()),
                );
              },
            ),
            const SizedBox(height: 15),
            // 📊 ADMIN DASHBOARD
            if (_profile != null && _profile!.email == 'admin@soko-langu.com')
              _button(
                icon: Icons.admin_panel_settings,
                text: context.tr('admin_dashboard'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminDashboardScreen(),
                    ),
                  );
                },
              ),
            const SizedBox(height: 15),
            // 🎵 MEDIA
            _button(
              icon: Icons.play_circle_outline,
              text: 'My Media',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MediaPlayerScreen()),
                );
              },
            ),
            const SizedBox(height: 15),
            // ⚙️ SETTINGS
            _button(
              icon: Icons.settings,
              text: context.tr('settings'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            const SizedBox(height: 15),
            const AdBanner(),
            const SizedBox(height: 15),
            // 🚪 LOGOUT
            GestureDetector(
              onTap: () async {
                await AuthService().logout();
              },
              child: Container(
                padding: const EdgeInsets.all(15),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    context.tr('logout'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierSection() {
    final tier = themeManager.currentTier;
    final Color tierColor;
    final String tierName;
    switch (tier) {
      case 'silver':
        tierColor = Colors.blueGrey;
        tierName = 'Silver';
        break;
      case 'premium':
        tierColor = Colors.amber;
        tierName = 'Premium';
        break;
      default:
        tierColor = Colors.green;
        tierName = 'Free';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tierColor.withValues(alpha: 0.1),
            tierColor.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tierColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          TierBadge(size: 40, showLabel: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tierName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: tierColor,
                  ),
                ),
                Text(
                  tier == 'free'
                      ? context.tr('free_plan_current')
                      : context.tr('plan_active'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          if (tier == 'free')
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PremiumUpgradeScreen(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: tierColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Upgrade',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _button({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.green),
            const SizedBox(width: 10),
            Text(
              text,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.38),
            ),
          ],
        ),
      ),
    );
  }
}
