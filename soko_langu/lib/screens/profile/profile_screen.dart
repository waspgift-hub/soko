import 'dart:ui' as ui;
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
import '../../services/ai/ai_service.dart';
import '../../widgets/account_switcher_sheet.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/premium_widgets.dart';
import '../../widgets/google_loading.dart';
import '../../app/routes.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;
  final ImagePicker _picker = ImagePicker();
  final UserService _userService = UserService();
  final WishlistService _wishlistService = WishlistService();
  UserProfile? _profile;
  String? _localImagePath;
  int _wishlistCount = 0;
  double _avgRating = 0;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() => _refreshKey++);
      _refreshProfile();
    }
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

    return KeyedSubtree(
      key: ValueKey('profile_$_refreshKey'),
      child: Scaffold(
      body: PremiumScaffold(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [cs.primary.withValues(alpha: 0.03), cs.surface],
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
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: _statCard(Icons.favorite_rounded, context.tr('wishlist'), '$_wishlistCount', cs)),
                              Container(width: 1, height: 40, color: cs.primary.withValues(alpha: 0.1)),
                              Expanded(child: _statCard(Icons.star_rounded, context.tr('rating'), _avgRating.toStringAsFixed(1), cs)),
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
                // AI Assistant mini chat
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppInsets.lg),
                  child: _AiChatBox(cs: cs),
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
      _ActionItem(Icons.swap_horiz_rounded, context.tr('accounts'), () => AccountSwitcherSheet.show(context)),
      _ActionItem(Icons.edit_rounded, context.tr('edit_profile'), () async { await context.push(AppRoutes.editProfile); _refreshProfile(); }),
      _ActionItem(Icons.favorite_rounded, context.tr('wishlist'), () => context.push(AppRoutes.wishlist)),
      _ActionItem(Icons.shopping_bag_rounded, context.tr('my_ads'), () => context.push(AppRoutes.myAds)),
      _ActionItem(Icons.store_rounded, context.tr('customize_shop'), () => context.push(AppRoutes.shopCustomization)),
      _ActionItem(Icons.dashboard_rounded, context.tr('dashboard'), () => context.push(AppRoutes.sellerDashboard)),
      _ActionItem(Icons.analytics_rounded, context.tr('analytics'), () {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) context.push(AppRoutes.sellerAnalytics, extra: uid);
      }),
      _ActionItem(Icons.auto_awesome_rounded, context.tr('ai_assistant'), () => context.push(AppRoutes.aiAssistant)),
      _ActionItem(Icons.explore_rounded, context.tr('discovery'), () => context.push(AppRoutes.discovery)),
      _ActionItem(Icons.receipt_long_rounded, context.tr('my_purchases'), () => context.push(AppRoutes.myPurchases)),
      _ActionItem(Icons.verified_rounded, context.tr('kyc'), () => context.push(AppRoutes.kyc)),
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

class _AiChatBox extends StatefulWidget {
  final ColorScheme cs;
  const _AiChatBox({required this.cs});

  @override
  State<_AiChatBox> createState() => _AiChatBoxState();
}

class _AiChatBoxState extends State<_AiChatBox> with TickerProviderStateMixin {
  final AiService _ai = AiService.instance;
  final TextEditingController _ctrl = TextEditingController();
  final List<String> _msgs = [];
  bool _loading = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _msgs.add(context.tr('ai_chat_greeting'));
    });
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _msgs.add(text);
      _loading = true;
    });
    _ctrl.clear();
    try {
      final reply = await _ai.sendMessage(text);
      if (mounted) setState(() => _msgs.add(reply));
    } catch (_) {
      if (mounted) setState(() => _msgs.add(context.tr('ai_generic_error')));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [cs.surface.withValues(alpha: 0.2), cs.surfaceContainerLow.withValues(alpha: 0.12)]
                  : [Colors.white.withValues(alpha: 0.88), Colors.white.withValues(alpha: 0.72)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: cs.primary.withValues(alpha: isDark ? 0.12 : 0.15),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.06),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, child) => Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.7)]),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.3 * _pulseAnim.value),
                            blurRadius: 12 * _pulseAnim.value,
                            spreadRadius: 1 * _pulseAnim.value,
                          ),
                        ],
                      ),
                      child: Icon(Icons.auto_awesome_rounded, color: cs.surface, size: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(context.tr('ai_assistant'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: cs.onSurface, letterSpacing: -0.3)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.aiAssistant),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(context.tr('open'), style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios, size: 10, color: cs.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) {
                    final msg = _msgs[i];
                    final isUser = i.isOdd;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isUser)
                            Container(
                              width: 24, height: 24,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.7)]),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.auto_awesome, size: 12, color: cs.surface),
                            ),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? cs.primary.withValues(alpha: 0.12)
                                    : cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.15 : 0.2),
                                borderRadius: BorderRadius.circular(18).copyWith(
                                  bottomRight: isUser ? const Radius.circular(6) : null,
                                  bottomLeft: isUser ? null : const Radius.circular(6),
                                ),
                                border: Border.all(
                                  color: cs.primary.withValues(alpha: isUser ? 0.08 : 0.03),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                msg,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isUser ? cs.primary : cs.onSurface,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const GoogleLoading(size: 18, strokeWidth: 2),
                      const SizedBox(width: 8),
                      Text(context.tr('typing'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: cs.surface.withValues(alpha: isDark ? 0.08 : 0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.15)),
                          ),
                          child: TextField(
                            controller: _ctrl,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: context.tr('type_question'),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              isDense: true,
                            ),
                            style: TextStyle(fontSize: 14, color: cs.onSurface),
                            cursorColor: cs.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _loading ? null : _send,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.7)]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: cs.primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Icon(Icons.send_rounded, color: cs.surface, size: 22),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

