import 'package:flutter/material.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../../services/user_service.dart';
import '../../notifiers/auth_notifier.dart';
import 'package:provider/provider.dart';
import '../../services/wishlist_service.dart';
import '../../extensions/context_tr.dart';
import '../../services/permission_service.dart';
import '../../widgets/account_switcher_sheet.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/premium_widgets.dart';
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
          .collection('reviews').where('sellerId', isEqualTo: uid).get();
      double total = 0;
      for (final doc in reviewSnap.docs) {
        total += (doc.data()['rating'] ?? 0).toDouble();
      }
      if (mounted) {
        setState(() { _wishlistCount = wishlist.length; _avgRating = reviewSnap.docs.isEmpty ? 0 : total / reviewSnap.docs.length; });
      }
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    var profile = await _userService.getProfile(user.uid);
    if (mounted) setState(() => _profile = profile);
    _loadStats(user.uid);
  }

  Future<void> _pickImage() async {
    final granted = await PermissionService.instance.requestWithDialog(context, AppPermission.storage);
    if (!granted) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery, maxWidth: 512, imageQuality: 80,
      );
      if (image != null) {
        setState(() => _localImagePath = image.path);
        final url = await _userService.uploadProfileImage(image.path);
        await _userService.updateProfileImage(url);
        await _loadProfile();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('photo_updated'))));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${context.tr('error')}: $e")));
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
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    final imageUrl = _localImagePath ?? _profile?.profileImage;

    return Scaffold(
      body: PremiumScaffold(
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 20),
            child: Column(
              children: [
                // Premium header
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [cs.primary.withValues(alpha: 0.08), cs.surface],
                    ),
                  ),
                  padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 24, bottom: 24),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 104, height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [cs.primary.withValues(alpha: 0.3), cs.surface],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: CircleAvatar(
                                radius: 49,
                                backgroundColor: cs.surface,
                                backgroundImage: imageUrl != null
                                    ? (imageUrl.startsWith('http') ? NetworkImage(imageUrl) as ImageProvider : FileImage(File(imageUrl)))
                                    : null,
                                child: imageUrl == null
                                    ? Text(
                                        _profile?.displayName.isNotEmpty == true ? _profile!.displayName[0].toUpperCase()
                                            : user?.displayName != null ? user!.displayName![0].toUpperCase()
                                            : user?.email != null ? user!.email![0].toUpperCase()
                                            : "U",
                                        style: TextStyle(fontSize: 40, color: cs.primary, fontWeight: FontWeight.bold),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          Positioned(bottom: 2, right: 2,
                            child: GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 8)],
                                ),
                                child: Icon(Icons.camera_alt, color: cs.onPrimary, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppInsets.lg),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _profile?.displayName.isNotEmpty == true ? _profile!.displayName : user?.displayName ?? context.tr('no_name'),
                            style: TextStyle(fontSize: AppFontSize.xxl, fontWeight: FontWeight.w700, color: cs.onSurface, letterSpacing: -0.3),
                          ),
                          if (_profile?.kycApproved == true) ...[
                            const SizedBox(width: AppInsets.sm),
                            const VerifiedBadge(size: 16),
                          ],
                        ],
                      ),
                      if (_profile?.bio.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppInsets.xxl),
                          child: Text(_profile!.bio, style: TextStyle(color: cs.onSurfaceVariant, fontSize: AppFontSize.md), textAlign: TextAlign.center),
                        ),
                      const SizedBox(height: AppInsets.xs),
                      Text(user?.email ?? context.tr('no_email'), style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: AppFontSize.sm)),
                      const SizedBox(height: AppInsets.lg),
                      // Stats
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppInsets.xl),
                        child: Row(
                          children: [
                            Expanded(child: _statCard(Icons.favorite_rounded, context.tr('wishlist'), '$_wishlistCount', cs)),
                            const SizedBox(width: AppInsets.md),
                            Expanded(child: _statCard(Icons.star_rounded, 'Rating', _avgRating.toStringAsFixed(1), cs)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppInsets.sm),
                // Action grid
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppInsets.lg),
                  child: _buildActionGrid(cs),
                ),
                const SizedBox(height: AppInsets.lg),
                // Settings
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppInsets.lg),
                  child: GlassCard(
                    onTap: () => context.push(AppRoutes.settings),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.settings_rounded, color: cs.primary, size: 22),
                        ),
                        const SizedBox(width: AppInsets.md),
                        Expanded(child: Text(context.tr('settings'), style: TextStyle(fontSize: AppFontSize.lg, fontWeight: FontWeight.w600, color: cs.onSurface))),
                        Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppInsets.lg),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppInsets.lg),
                  child: AdBanner(),
                ),
                const SizedBox(height: AppInsets.lg),
                // Logout
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppInsets.lg),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await context.read<AuthNotifier>().logout();
                      },
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: Text(context.tr('logout')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppInsets.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value, ColorScheme cs) {
    return GlassCard(
      child: Column(
        children: [
          Icon(icon, color: cs.primary, size: 22),
          const SizedBox(height: AppInsets.xs),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppFontSize.lg, color: cs.onSurface)),
          Text(label, style: TextStyle(fontSize: AppFontSize.xs, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildActionGrid(ColorScheme cs) {
    final user = FirebaseAuth.instance.currentUser;
    final isAdmin = _profile?.email == 'admin@soko-langu.com' ||
        user?.email?.toLowerCase() == 'admin@soko-langu.com';
    final actions = [
      _ActionItem(Icons.swap_horiz_rounded, 'Accounts', () => AccountSwitcherSheet.show(context)),
      _ActionItem(Icons.edit_rounded, context.tr('edit_profile'), () async { await context.push(AppRoutes.editProfile); _refreshProfile(); }),
      _ActionItem(Icons.favorite_rounded, context.tr('wishlist'), () => context.push(AppRoutes.wishlist)),
      _ActionItem(Icons.shopping_bag_rounded, context.tr('my_ads'), () => context.push(AppRoutes.myAds)),
      _ActionItem(Icons.store_rounded, context.tr('customize_shop'), () => context.push(AppRoutes.shopCustomization)),
      _ActionItem(Icons.dashboard_rounded, context.tr('dashboard'), () => context.push(AppRoutes.sellerDashboard)),
      _ActionItem(Icons.analytics_rounded, 'Takwimu', () => context.push(AppRoutes.sellerAnalytics)),
      _ActionItem(Icons.explore_rounded, context.tr('discovery'), () => context.push(AppRoutes.discovery)),
      _ActionItem(Icons.library_music_rounded, context.tr('music_player'), () => context.push(AppRoutes.audioList)),
      _ActionItem(Icons.receipt_long_rounded, 'Manunuzi Yangu', () => context.push(AppRoutes.myPurchases)),
      _ActionItem(Icons.verified_rounded, 'KYC', () => context.push(AppRoutes.kyc)),
    ];
    if (isAdmin) {
      actions.add(_ActionItem(Icons.admin_panel_settings_rounded, context.tr('admin_dashboard'), () => context.push(AppRoutes.admin)));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 1.0, crossAxisSpacing: 10, mainAxisSpacing: 10,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final item = actions[index];
        return GlassCard(
          onTap: item.onTap,
          padding: const EdgeInsets.symmetric(vertical: AppInsets.lg, horizontal: AppInsets.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: cs.primary, size: 24),
              ),
              const SizedBox(height: AppInsets.sm),
              Text(item.label, style: TextStyle(fontSize: AppFontSize.xs, color: cs.onSurface, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      },
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _ActionItem(this.icon, this.label, this.onTap);
}
