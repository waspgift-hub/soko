import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/discovery_screen.dart';
import '../screens/chat/chat_inbox_screen.dart';
import '../services/user_service.dart';
import '../services/chat_service.dart';
import '../models/chat_room.dart';
import '../app/routes.dart';
import '../extensions/context_tr.dart';
import '../utils/responsive.dart';
import 'auth_wall.dart';
import 'profile_mini_player.dart';
import 'package:go_router/go_router.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  int _maxVisitedIndex = 0;
  final UserService _userService = UserService();
  String? _profilePhotoUrl;
  int _unreadTotal = 0;
  StreamSubscription<List<ChatRoom>>? _chatSub;

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
      // Music removed.
      case 2:
        return const SizedBox.shrink();
      case 3:
        // Sell is the central FAB, not a stacked tab.
        return const SizedBox.shrink();
      case 4:
        return const ChatInboxScreen();
      case 5:
        return const ProfilePage();
      default:
        return const SizedBox.shrink();
    }
  }

  void _selectTab(int index) {
    // Guest wall: Sell, Chat and Profile need an account. Music (2) is the
    // user's own library, so it stays reachable without signing in.
    if (index >= 3 && FirebaseAuth.instance.currentUser == null) {
      requireAuth(context);
      return;
    }
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
      if (index > _maxVisitedIndex) _maxVisitedIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadProfilePhoto();
    _subscribeUnread();
  }

  void _subscribeUnread() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _chatSub = ChatService().getRooms().listen((rooms) {
      if (!mounted) return;
      final total = rooms
          .where((r) => !r.archivedBy.contains(uid))
          .fold<int>(0, (sum, r) => sum + r.unreadCountFor(uid));
      if (total != _unreadTotal) setState(() => _unreadTotal = total);
    });
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
    _chatSub?.cancel();
    super.dispose();
  }

  static Duration _motion(BuildContext context, int ms) =>
      (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
      ? Duration.zero
      : Duration(milliseconds: ms);

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
            child: AnimatedSwitcher(
              duration: _motion(context, 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              child: KeyedSubtree(
                key: ValueKey<int>(_currentIndex),
                child: IndexedStack(
                  index: _currentIndex,
                  children: [
                    for (var i = 0; i <= _maxVisitedIndex; i++)
                      RepaintBoundary(key: ValueKey('tab_$i'), child: _buildTabScreen(i)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [const ProfileMiniPlayer(), _buildGlassNavBar(cs)],
            ),
    );
  }

  Widget _buildGlassNavBar(ColorScheme cs) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final isDark = cs.brightness == Brightness.dark;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final surface = isDark ? cs.surfaceContainerHigh : cs.surface;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset > 0 ? bottomInset + 6 : 10),
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface.withValues(alpha: isDark ? 0.98 : 0.99),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.28 : 0.55),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SizedBox(
            height: 66,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTab(
                    0,
                    Icons.storefront_outlined,
                    Icons.storefront_rounded,
                    context.tr('home'),
                    cs,
                    reduceMotion,
                  ),
                  _buildTab(
                    1,
                    Icons.explore_outlined,
                    Icons.explore_rounded,
                    context.tr('discovery'),
                    cs,
                    reduceMotion,
                  ),
                  _buildSellTab(cs),
                  _buildTab(
                    4,
                    Icons.chat_bubble_outline_rounded,
                    Icons.chat_bubble_rounded,
                    context.tr('chat'),
                    cs,
                    reduceMotion,
                    badgeCount: _unreadTotal,
                  ),
                  _buildProfileTab(cs, reduceMotion),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _selectedTabDecoration(ColorScheme cs) => BoxDecoration(
    color: cs.primary.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(18),
  );

  Widget _buildTab(
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
    ColorScheme cs,
    bool reduceMotion, {
    int badgeCount = 0,
  }) {
    final isSelected = _currentIndex == index;
    final anim = reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        onTap: () => _selectTab(index),
        child: InkWell(
          onTap: () => _selectTab(index),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: anim,
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: isSelected ? _selectedTabDecoration(cs) : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  duration: anim,
                  scale: isSelected ? 1.0 : 0.94,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        isSelected ? activeIcon : icon,
                        color: isSelected
                            ? cs.primary
                            : cs.onSurfaceVariant.withValues(alpha: 0.82),
                        size: 23,
                      ),
                      if (badgeCount > 0)
                        Positioned(
                          top: -6,
                          right: -10,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.error,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cs.surface, width: 1.4),
                            ),
                            child: Text(
                              badgeCount > 99 ? '99+' : '$badgeCount',
                              style: TextStyle(
                                color: cs.onError,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: -0.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTab(ColorScheme cs, bool reduceMotion) {
    final isSelected = _currentIndex == 5;
    final anim = reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: context.tr('profile'),
        onTap: () => _selectTab(5),
        child: InkWell(
          onTap: () => _selectTab(5),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: anim,
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: isSelected ? _selectedTabDecoration(cs) : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: anim,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? cs.primary : Colors.transparent,
                      width: 1.8,
                    ),
                  ),
                  padding: const EdgeInsets.all(1.5),
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: cs.primary.withValues(alpha: 0.12),
                    backgroundImage: _profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty
                        ? NetworkImage(_profilePhotoUrl!)
                        : null,
                    child: _profilePhotoUrl == null || _profilePhotoUrl!.isEmpty
                        ? Icon(
                            isSelected ? Icons.person_rounded : Icons.person_outline_rounded,
                            color: isSelected ? cs.primary : cs.onSurfaceVariant,
                            size: 14,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr('profile'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: -0.15,
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
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _openAddProduct,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.38),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(Icons.add_rounded, color: cs.onPrimary, size: 26),
              ),
              const SizedBox(height: 2),
              Text(
                context.tr('sell'),
                style: TextStyle(
                  fontSize: 10,
                  color: cs.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
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
    // Use GoRouter so auth redirect guard and deep-link stack stay intact.
    context.push(AppRoutes.addProduct);
  }

  Widget _buildSidebar(ColorScheme cs) {
    final navItems = [
      _NavItem(Icons.storefront_outlined, Icons.storefront_rounded, context.tr('home'), 0),
      _NavItem(Icons.diamond_outlined, Icons.diamond_rounded, context.tr('discovery'), 1),
      _NavItem(
        Icons.chat_outlined,
        Icons.chat_rounded,
        context.tr('chat'),
        4,
        badgeCount: _unreadTotal,
      ),
      _NavItem(Icons.person_outline, Icons.person_rounded, context.tr('profile'), 5),
    ];

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
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
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.store_rounded, color: cs.onPrimary, size: 20),
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
                      color: isSelected ? cs.primary.withValues(alpha: 0.08) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _selectTab(item.index),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  fontSize: 14,
                                ),
                              ),
                              const Spacer(),
                              if (item.badgeCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.error,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                                    style: TextStyle(
                                      color: cs.onError,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              if (isSelected && item.badgeCount == 0)
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
                        context.push(AppRoutes.addProduct);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                              child: Icon(Icons.add_rounded, color: cs.onPrimary, size: 20),
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
  final int badgeCount;
  const _NavItem(this.icon, this.activeIcon, this.label, this.index, {this.badgeCount = 0});
}
