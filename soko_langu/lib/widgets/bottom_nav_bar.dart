import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/discovery_screen.dart';
import '../screens/chat/chat_inbox_screen.dart';
import '../screens/home/add_product_screen.dart';
import '../services/user_service.dart';
import '../app/app_transitions.dart';
import '../extensions/context_tr.dart';
import '../main.dart';
import '../utils/responsive.dart';
import 'auth_wall.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  int _maxVisitedIndex = 0;
  Timer? _adTimer;
  final UserService _userService = UserService();
  String? _profilePhotoUrl;

  // Tabs are built lazily on first visit (IndexedStack keeps them alive
  // afterwards). Building all of them at app start means offstage subtrees
  // (BackdropFilter-heavy, e.g. ProfilePage) get composited before they are
  // ever visible, which can leave a stale/grey frame when first selected.
  Widget _buildTabScreen(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return const DiscoveryScreen();
      case 2:
        return const SizedBox.shrink();
      case 3:
        return const ChatInboxScreen();
      case 4:
        return const ProfilePage();
      default:
        return const SizedBox.shrink();
    }
  }

  void _selectTab(int index) {
    // Guest wall: Sell, Chat and Profile need an account.
    if ((index == 2 || index == 3 || index == 4) &&
        FirebaseAuth.instance.currentUser == null) {
      requireAuth(context);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
      if (index > _maxVisitedIndex) _maxVisitedIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    interstitialAdService.load();
    _adTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      interstitialAdService.tryShow();
    });
    _loadProfilePhoto();
  }

  Future<void> _loadProfilePhoto() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final profile = await _userService.getProfile(uid);
    if (profile?.profileImage != null && mounted) {
      setState(() => _profilePhotoUrl = profile!.profileImage);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      interstitialAdService.tryShow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      extendBody: true,
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(cs),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              // RepaintBoundary isolates each tab's compositor layer so a
              // BackdropFilter in one tab cannot stall another tab's paint
              children: [
                for (var i = 0; i <= _maxVisitedIndex; i++)
                  RepaintBoundary(key: ValueKey('tab_$i'), child: _buildTabScreen(i)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop ? null : _buildGlassNavBar(cs),
    );
  }

  Widget _buildGlassNavBar(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    final navBg = isDark
        ? const Color(0xFF0D1A18).withValues(alpha: 0.82)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.82);
    final navBorder = isDark
        ? const Color(0x2AFFFFFF)
        : const Color(0x08000000);
    // Lift the bar above the Android gesture/navigation bar (edge-to-edge
    // is enforced at targetSdk 36); MediaQuery.padding.bottom is 0 on
    // legacy devices, so this is safe on both.
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 12),
      child: RepaintBoundary(
        child: SizedBox(
          height: 72,
          child: Container(
            decoration: BoxDecoration(
              color: navBg,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: navBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildTab(
                  0,
                  Icons.storefront_outlined,
                  Icons.storefront_rounded,
                  context.tr('home'),
                  cs,
                ),
                _buildTab(
                  1,
                  Icons.diamond_outlined,
                  Icons.diamond_rounded,
                  context.tr('discovery'),
                  cs,
                ),
                _buildSellTab(cs),
                _buildTab(
                  3,
                  Icons.chat_outlined,
                  Icons.chat_rounded,
                  context.tr('chat'),
                  cs,
                ),
                _buildProfileTab(cs),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
    ColorScheme cs,
  ) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        onTap: () => _selectTab(index),
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: () => _selectTab(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? cs.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: isSelected ? 1 : 0.9,
                  child: Icon(
                    isSelected ? activeIcon : icon,
                    color: isSelected
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.45),
                    size: 24,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.45),
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTab(ColorScheme cs) {
    final isSelected = _currentIndex == 4;
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: context.tr('profile'),
        onTap: () => _selectTab(4),
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: () => _selectTab(4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? cs.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: isSelected ? 1 : 0.9,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: cs.primary.withValues(alpha: 0.12),
                    backgroundImage: _profilePhotoUrl != null &&
                            _profilePhotoUrl!.isNotEmpty
                        ? NetworkImage(_profilePhotoUrl!)
                        : null,
                    child: _profilePhotoUrl == null || _profilePhotoUrl!.isEmpty
                        ? Icon(
                            Icons.person_outline,
                            color: isSelected
                                ? cs.primary
                                : cs.onSurface.withValues(alpha: 0.45),
                            size: 16,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr('profile'),
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.45),
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSellTab(ColorScheme cs) {
    return Expanded(
      child: Semantics(
        button: true,
        label: context.tr('sell'),
        onTap: _openAddProduct,
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: _openAddProduct,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [cs.primary, cs.primary.withValues(alpha: 0.72)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.32),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(Icons.add_rounded, color: cs.onPrimary, size: 26),
              ),
              const SizedBox(height: 1),
              Text(
                context.tr('sell'),
                style: TextStyle(
                  fontSize: 10,
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAddProduct() {
    HapticFeedback.mediumImpact();
    Navigator.of(
      context,
    ).push(buildAppRoute(builder: (_) => const AddProductScreen()));
  }

  Widget _buildSidebar(ColorScheme cs) {
    final navItems = [
      _NavItem(
        Icons.storefront_outlined,
        Icons.storefront_rounded,
        context.tr('home'),
        0,
      ),
      _NavItem(
        Icons.diamond_outlined,
        Icons.diamond_rounded,
        context.tr('discovery'),
        1,
      ),
      _NavItem(Icons.chat_outlined, Icons.chat_rounded, context.tr('chat'), 3),
      _NavItem(
        Icons.person_outline,
        Icons.person_rounded,
        context.tr('profile'),
        4,
      ),
    ];

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.store_rounded,
                    color: cs.onPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Soko Vibe',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              children: [
                ...navItems.map((item) {
                  final isSelected = _currentIndex == item.index;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cs.primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _selectTab(item.index),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? item.activeIcon : item.icon,
                                color: isSelected
                                    ? cs.primary
                                    : cs.onSurface.withValues(alpha: 0.5),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                item.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? cs.onSurface
                                      : cs.onSurface.withValues(alpha: 0.6),
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  fontSize: 14,
                                ),
                              ),
                              const Spacer(),
                              if (isSelected)
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const Divider(height: 16),
                // Sell button in sidebar
                Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.of(context).push(
                            buildAppRoute(
                              builder: (_) => const AddProductScreen(),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      cs.primary,
                                      cs.primary.withValues(alpha: 0.7),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.add_rounded,
                                  color: cs.onPrimary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                context.tr('sell'),
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  const _NavItem(this.icon, this.activeIcon, this.label, this.index);
}
