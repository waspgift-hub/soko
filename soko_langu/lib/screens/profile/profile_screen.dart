import 'package:flutter/material.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../order/my_orders_screen.dart';
import '../chat/chats_list_screen.dart';
import '../call/call_history_screen.dart';
import '../media/media_player_screen.dart';
import 'settings_screen.dart';
import 'wishlist_screen.dart';
import 'my_ads_screen.dart';
import 'edit_profile_screen.dart';
import 'seller_dashboard_screen.dart';
import '../admin/admin_dashboard_screen.dart';
import '../wallet/buy_coins_screen.dart';
import '../wallet/viewer_earnings_screen.dart';
import '../media/playlists_screen.dart';
import '../../services/user_service.dart';
import '../../services/auth_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/verified_badge.dart';
import '../../main.dart';
import '../../widgets/tier_badge.dart';
import '../../widgets/ad_banner.dart';
import 'premium_upgrade_screen.dart';
import 'shop_customization_screen.dart';

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
        ).showSnackBar(SnackBar(content: Text("${context.tr('error')}: $e")));
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
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            children: [
              // Mint gradient header
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFD8F3DC), Color(0xFFF0F9F1)],
                  ),
                ),
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 16,
                  bottom: 24,
                ),
                child: Column(
                  children: [
                    // Avatar
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white,
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
                                    color: Color(0xFF2D6A4F),
                                    fontWeight: FontWeight.bold,
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
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF2D6A4F),
                                    Color(0xFF40916C),
                                  ],
                                ),
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
                    const SizedBox(height: 12),
                    // Name + badge
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _profile?.displayName.isNotEmpty == true
                              ? _profile!.displayName
                              : user?.displayName ?? context.tr('no_name'),
                          style: const TextStyle(
                            color: Color(0xFF1B4332),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        VerifiedBadge(
                          tier: _profile?.accountTier,
                          isAdmin: _profile?.email == 'admin@soko-langu.com',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (_profile?.bio.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _profile!.bio,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      user?.email ?? context.tr('no_email'),
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    // Stats cards
                    _buildStatsRow(),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Tier section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTierSection(),
              ),
              const SizedBox(height: 16),
              // Action grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildActionGrid(),
              ),
              const SizedBox(height: 16),
              // Settings
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildSettingsSection(),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: AdBanner(),
              ),
              const SizedBox(height: 16),
              // Logout
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildLogoutButton(),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _statCard(Icons.favorite, context.tr('wishlist'), '0'),
          _statCard(Icons.shopping_bag, context.tr('my_orders'), '0'),
          _statCard(Icons.star, 'Rating', '0'),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2D6A4F).withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF40916C), size: 22),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Color(0xFF2D6A4F),
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
        tierColor = const Color(0xFF2D6A4F);
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
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2D6A4F), Color(0xFF40916C)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  context.tr('upgrade_now'),
                  style: const TextStyle(
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

  Widget _buildActionGrid() {
    final isAdmin = _profile?.email == 'admin@soko-langu.com';

    final actions = [
      _ActionItem(Icons.edit, context.tr('edit_profile'), () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EditProfileScreen()),
        );
        _refreshProfile();
      }),
      _ActionItem(Icons.favorite, context.tr('wishlist'), () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WishlistScreen()),
        );
      }),
      _ActionItem(Icons.receipt_long, context.tr('my_orders'), () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
        );
      }),
      _ActionItem(Icons.shopping_bag, context.tr('my_ads'), () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyAdsScreen()),
        );
      }),
      _ActionItem(Icons.store, context.tr('customize_shop'), () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ShopCustomizationScreen()),
        );
      }),
      _ActionItem(Icons.dashboard, context.tr('dashboard'), () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SellerDashboardScreen()),
        );
      }),
      _ActionItem(Icons.chat_bubble, context.tr('chats'), () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChatsListScreen()),
        );
      }),
      _ActionItem(Icons.phone, context.tr('call_history'), () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CallHistoryScreen()),
        );
      }),
      _ActionItem(Icons.play_circle_outline, context.tr('my_media'), () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MediaPlayerScreen()),
        );
      }),
      _ActionItem(Icons.monetization_on, context.tr('buy_coins'), () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BuyCoinsScreen()),
        );
      }),
      _ActionItem(Icons.visibility, context.tr('earn_coins'), () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ViewerEarningsScreen()),
        );
      }),
      _ActionItem(Icons.queue_music, context.tr('playlists'), () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
        );
      }),
    ];

    if (isAdmin) {
      actions.add(
        _ActionItem(
          Icons.admin_panel_settings,
          context.tr('admin_dashboard'),
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
            );
          },
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.95,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final item = actions[index];
        return GestureDetector(
          onTap: item.onTap,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2D6A4F).withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9F1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    item.icon,
                    color: const Color(0xFF2D6A4F),
                    size: 24,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF2D6A4F),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsSection() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2D6A4F).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.settings, color: Color(0xFF2D6A4F)),
            const SizedBox(width: 12),
            Text(
              context.tr('settings'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2D6A4F),
              ),
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: () async {
        await AuthService().logout();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red[400]!, Colors.red[300]!],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                context.tr('logout'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _ActionItem(this.icon, this.label, this.onTap);
}
