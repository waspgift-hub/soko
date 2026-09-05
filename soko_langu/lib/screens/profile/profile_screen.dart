import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
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
import '../../utils/phone_utils.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  final UserService _userService = UserService();
  final WishlistService _wishlistService = WishlistService();
  UserProfile? _profile;
  String? _localImagePath;
  bool _avatarError = false;
  int _wishlistCount = 0;
  bool _isLoading = true;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _loadProfile();
    }
    // Reactive auth: covers the cold-start race where currentUser is still
    // null in initState, and handles sign-in/sign-out without one-shot
    // subscriptions that can miss the emission
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      if (!mounted) return;
      if (u != null) {
        if (!_isLoading && _profile == null) {
          _loadProfile();
        }
      } else {
        setState(() {
          _profile = null;
          _localImagePath = null;
          _wishlistCount = 0;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshProfile();
    }
  }

  Future<void> _loadStats(String uid) async {
    try {
      final wishlist = await _wishlistService.getWishlist();
      if (mounted) {
        setState(() { _wishlistCount = wishlist.length; });
      }
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _avatarError = false; });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { if (mounted) setState(() => _isLoading = false); return; }
    var profile = await _userService.getProfile(user.uid);
    if (mounted) setState(() { _profile = profile; _isLoading = false; });
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
        setState(() { _localImagePath = image.path; _avatarError = false; });
        final oldUrl = _profile?.profileImage ?? '';
        final url = await _userService.uploadProfileImage(image.path);
        await _userService.updateProfileImage(url);
        await _userService.deleteProfileImage(oldUrl);
        await _loadProfile();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('photo_updated'))));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.trError(e))));
      }
    }
  }

  Future<void> _refreshProfile() async {
    _localImagePath = null;
    await _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    final imageUrl = _localImagePath ?? _profile?.profileImage;

    if (_profile == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: _isLoading
            ? const _ProfileSkeleton()
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline_rounded, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text(context.tr('profile_not_found'), style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: _loadProfile,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(context.tr('retry')),
                      ),
                    ],
                  ),
                ),
              ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      body: PremiumScaffold(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white, cs.surface],
            ),
          ),
          child: SafeArea(
          top: false,
          bottom: false,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 80),
            child: Column(
              children: [
                // Premium header
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white, cs.surface],
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
                                colors: [Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white, cs.surface],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: CircleAvatar(
                                radius: 49,
                                backgroundColor: cs.surface,
                                // Empty string (default) or a failed load must
                                // fall back to the person icon, not a blank ring.
                                backgroundImage: (imageUrl != null &&
                                        imageUrl.isNotEmpty &&
                                        !_avatarError)
                                    ? (imageUrl.startsWith('http')
                                        ? NetworkImage(imageUrl) as ImageProvider
                                        : FileImage(File(imageUrl)))
                                    : null,
                                onBackgroundImageError:
                                    (imageUrl != null && imageUrl.isNotEmpty)
                                        ? (_, _) {
                                            if (mounted) {
                                              setState(() => _avatarError = true);
                                            }
                                          }
                                        : null,
                                child: (imageUrl == null || imageUrl.isEmpty || _avatarError)
                                    ? Icon(
                                        Icons.person_outline_rounded,
                                        color: cs.primary,
                                        size: 48,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          Positioned(bottom: 2, right: 2,
                            child: Semantics(
                              button: true,
                              label: context.tr('change_profile_picture'),
                              onTap: _pickImage,
                              child: GestureDetector(
                                excludeFromSemantics: true,
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
                      if (_profile?.phone?.isNotEmpty == true) ...[
                        const SizedBox(height: 2),
                        Text(
                          PhoneUtils.formatForDisplay(_profile!.phone!),
                          style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: AppFontSize.sm),
                        ),
                      ],
                      const SizedBox(height: AppInsets.lg),
                      // Stats
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppInsets.xl),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: _statCard(Icons.favorite_rounded, context.tr('wishlist'), '$_wishlistCount', cs)),
                            ],
                          ),
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
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.primary.withValues(alpha: 0.3), width: 1.2),
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(2),
      child: Column(
        children: [
          Icon(icon, color: cs.primary, size: 22),
          const SizedBox(height: 4),
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
      _ActionItem(Icons.switch_account_rounded, context.tr('accounts'), () => AccountSwitcherSheet.show(context)),
      _ActionItem(Icons.edit_rounded, context.tr('edit_profile'), () async { await context.push(AppRoutes.editProfile); _refreshProfile(); }),
      _ActionItem(Icons.favorite_rounded, context.tr('wishlist'), () => context.push(AppRoutes.wishlist)),
      _ActionItem(Icons.shopping_bag_rounded, context.tr('my_ads'), () => context.push(AppRoutes.myAds)),
      _ActionItem(Icons.store_rounded, context.tr('customize_shop'), () => context.push(AppRoutes.shopCustomization)),
      _ActionItem(Icons.dashboard_rounded, context.tr('dashboard'), () => context.push(AppRoutes.sellerDashboard)),
      _ActionItem(Icons.auto_awesome_rounded, context.tr('ai_assistant'), () => context.push(AppRoutes.aiAssistant)),
      _ActionItem(Icons.explore_rounded, context.tr('discovery'), () => context.push(AppRoutes.discovery)),
      _ActionItem(Icons.receipt_long_rounded, context.tr('my_purchases'), () => context.push(AppRoutes.myPurchases)),
      _ActionItem(Icons.verified_rounded, context.tr('kyc'), () => context.push(AppRoutes.kyc)),
    ];
    if (isAdmin) {
      actions.add(_ActionItem(Icons.admin_panel_settings_rounded, context.tr('admin_dashboard'), () => context.push(AppRoutes.admin)));
    }
    final tileWidth = (MediaQuery.of(context).size.width - 32 - 20) / 3;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: actions.map((item) {
        return SizedBox(
          width: tileWidth,
          height: tileWidth,
          child: GlassCard(
            onTap: item.onTap,
            padding: const EdgeInsets.symmetric(vertical: AppInsets.lg, horizontal: AppInsets.sm),
            borderColor: cs.primary.withValues(alpha: 0.35),
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
                Text(item.label, style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurface, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _ActionItem(this.icon, this.label, this.onTap);
}


class _ProfileSkeleton extends StatefulWidget {
  const _ProfileSkeleton();

  @override
  State<_ProfileSkeleton> createState() => _ProfileSkeletonState();
}

class _ProfileSkeletonState extends State<_ProfileSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _shimmer = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[850]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    Widget block(double w, double h, [double radius = 8]) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            colors: [base, highlight, base],
            stops: [
              (_shimmer.value - 0.35).clamp(0.0, 1.0),
              _shimmer.value.clamp(0.0, 1.0),
              (_shimmer.value + 0.35).clamp(0.0, 1.0),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            children: [
              block(96, 96, 48),
              const SizedBox(height: 16),
              block(180, 16),
              const SizedBox(height: 8),
              block(120, 12),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [block(70, 14), block(70, 14), block(70, 14)],
              ),
              const SizedBox(height: 28),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
                children: List.generate(6, (_) => block(double.infinity, double.infinity, 16)),
              ),
            ],
          ),
        );
      },
    );
  }
}

