import 'package:flutter/material.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../../services/user_service.dart';
import '../../services/auth_service.dart';
import '../../services/wishlist_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/account_switcher_sheet.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/verified_badge.dart';
import '../../app/routes.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final ImagePicker _picker = ImagePicker();
  final UserService _userService = UserService();
  final WishlistService _wishlistService = WishlistService();
  UserProfile? _profile;
  String? _localImagePath;
  int _wishlistCount = 0;
  double _avgRating = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadStats(String uid) async {
    try {
      final wishlist = await _wishlistService.getWishlist();
      final reviewSnap = await FirebaseFirestore.instance
          .collection('reviews')
          .where('sellerId', isEqualTo: uid)
          .get();
      double total = 0;
      for (final doc in reviewSnap.docs) {
        total += (doc.data()['rating'] ?? 0).toDouble();
      }
      if (mounted) {
        setState(() {
          _wishlistCount = wishlist.length;
          _avgRating = reviewSnap.docs.isEmpty
              ? 0
              : total / reviewSnap.docs.length;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    var profile = await _userService.getProfile(user.uid);
    if (mounted) {
      setState(() => _profile = profile);
    }
    _loadStats(user.uid);
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 80,
      );
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
    super.build(context);
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
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Theme.of(context).colorScheme.tertiaryContainer, Theme.of(context).colorScheme.surfaceContainerLow],
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
                          backgroundColor: Theme.of(context).colorScheme.surface,
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
                                  style:  TextStyle(
                                    fontSize: 40,
                                    color: Theme.of(context).colorScheme.primary,
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
                              decoration:  BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.tertiary,
                                  ],
                                ),
                                shape: BoxShape.circle,
                              ),
                              child:  Icon(
                                Icons.camera_alt,
                                color: Theme.of(context).colorScheme.surface,
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
                          style:  TextStyle(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_profile?.kycApproved == true)
                          const VerifiedBadge(size: 16),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (_profile?.bio.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _profile!.bio,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      user?.email ?? context.tr('no_email'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    // Stats cards
                    _buildStatsRow(),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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
          _statCard(Icons.favorite, context.tr('wishlist'), '$_wishlistCount'),
          _statCard(Icons.star, 'Rating', _avgRating.toStringAsFixed(1)),
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
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionGrid() {
    final isAdmin = _profile?.email == 'admin@soko-langu.com';

    final actions = [
      _ActionItem(Icons.swap_horiz_rounded, 'Accounts', () {
        AccountSwitcherSheet.show(context);
      }),
      _ActionItem(Icons.edit, context.tr('edit_profile'), () async {
        await context.push(AppRoutes.editProfile);
        _refreshProfile();
      }),
      _ActionItem(Icons.favorite, context.tr('wishlist'), () {
        context.push(AppRoutes.wishlist);
      }),
      _ActionItem(Icons.shopping_bag, context.tr('my_ads'), () {
        context.push(AppRoutes.myAds);
      }),
      _ActionItem(Icons.store, context.tr('customize_shop'), () {
        context.push(AppRoutes.shopCustomization);
      }),
      _ActionItem(Icons.dashboard, context.tr('dashboard'), () {
        context.push(AppRoutes.sellerDashboard);
      }),
      _ActionItem(Icons.explore, context.tr('discovery'), () {
        context.push(AppRoutes.discovery);
      }),
      _ActionItem(Icons.play_circle_outline, context.tr('audio'), () {
        context.push(AppRoutes.audioList);
      }),
      _ActionItem(Icons.receipt_long_outlined, 'Manunuzi Yangu', () {
        context.push(AppRoutes.myPurchases);
      }),
      _ActionItem(Icons.verified_outlined, 'KYC', () {
        context.push(AppRoutes.kyc);
      }),
    ];

    if (isAdmin) {
      actions.add(
        _ActionItem(
          Icons.admin_panel_settings,
          context.tr('admin_dashboard'),
          () => context.push(AppRoutes.admin),
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
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    item.icon,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface,
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
      onTap: () => context.push(AppRoutes.settings),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(
              context.tr('settings'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
            colors: [Theme.of(context).colorScheme.error, Theme.of(context).colorScheme.error.withValues(alpha: 0.85)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout, color: Theme.of(context).colorScheme.surface, size: 18),
              const SizedBox(width: 8),
              Text(
                context.tr('logout'),
                style:  TextStyle(
                  color: Theme.of(context).colorScheme.surface,
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
