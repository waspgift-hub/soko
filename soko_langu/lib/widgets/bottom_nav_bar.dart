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
import '../services/chat_service.dart';
import '../models/chat_room.dart';
import '../app/app_transitions.dart';
import '../extensions/context_tr.dart';
import '../main.dart';
import '../theme/neumorphic.dart';
import '../utils/responsive.dart';
import 'auth_wall.dart';
import 'profile_mini_player.dart';

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
    WidgetsBinding.instance.removeObserver(this);
    _adTimer?.cancel();
    _chatSub?.cancel();
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
      bottomNavigationBar: isDesktop
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [const ProfileMiniPlayer(), _buildGlassNavBar(cs)],
            ),
    );
  }

  Widget _buildGlassNavBar(ColorScheme cs) {
    // The pill is FLAT, deliberately deviating from the `navBar` raised style
    // in SurfacePolicy: it is a persistent element that is on screen for the
    // whole session, so a soft-UI extrusion there reads as noise rather than
    // emphasis. One directional shadow plus a hairline edge is enough to lift
    // it off the content behind it. The bar's single soft accent is the Sell
    // FAB, which is a real high-commitment control.
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 12),
      child: RepaintBoundary(
        child: SizedBox(
          height: 72,
          child: Container(
            decoration: BoxDecoration(
              color: Neu.flatFill(cs.brightness),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: Neu.grooveColor(cs.brightness),
                width: 0.5,
              ),
              boxShadow: Neu.flat(NeuFlatDepth.rest, cs.brightness),
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
                  badgeCount: _unreadTotal,
                ),
                _buildProfileTab(cs),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// FLAT selected-tab background: a translucent brand-green tint, matching the
  /// desktop sidebar so the two nav surfaces read as one system. Previously a
  /// `Neu.inset` groove, which put a second soft-UI treatment next to the pill
  /// and the FAB and made the bar read as entirely soft-UI.
  BoxDecoration _selectedTabDecoration(ColorScheme cs) => BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
      );

  Widget _buildTab(
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
    ColorScheme cs, {
    int badgeCount = 0,
  }) {
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
            decoration:
                isSelected ? _selectedTabDecoration(cs) : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: isSelected ? 1 : 0.9,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        isSelected ? activeIcon : icon,
                        color: isSelected
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.45),
                        size: 24,
                      ),
                      if (badgeCount > 0)
                        Positioned(
                          top: -6,
                          right: -10,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.error,
                              borderRadius: BorderRadius.circular(12),
                              // Ring in the pill's own fill so the badge reads as
                              // a cutout against it. Previously used the scaffold
                              // colour, which matched the old grey soft-UI base
                              // and would have left a pale halo on the flat fill.
                              border: Border.all(
                                color: Neu.flatFill(cs.brightness),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              badgeCount > 99 ? '99+' : '$badgeCount',
                              style: TextStyle(
                                color: cs.onError,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
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
            decoration:
                isSelected ? _selectedTabDecoration(cs) : null,
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
                  color: cs.primary,
                  shape: BoxShape.circle,
                  // The bar's one soft-UI accent. Selling is the highest
                  // commitment action available here, and now that the pill and
                  // the selected tab are flat this is the only extruded element
                  // left — which is what gives it its emphasis. Tinted dual
                  // shadow so the green reads as extruded from the flat pill.
                  boxShadow: Neu.raisedHue(4, cs.primary),
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
      _NavItem(Icons.chat_outlined, Icons.chat_rounded, context.tr('chat'), 3,
        badgeCount: _unreadTotal),
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
                    color: cs.primary,
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
                              if (item.badgeCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.error,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    item.badgeCount > 99
                                        ? '99+'
                                        : '${item.badgeCount}',
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
                                  color: cs.primary,
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
  final int badgeCount;
  const _NavItem(
    this.icon,
    this.activeIcon,
    this.label,
    this.index, {
    this.badgeCount = 0,
  });
}
