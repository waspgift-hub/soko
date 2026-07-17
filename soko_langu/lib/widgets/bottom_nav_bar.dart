import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/discovery_screen.dart';
import '../screens/ai/ai_assistant_screen.dart';
import '../screens/chat/chats_list_screen.dart';
import '../screens/home/add_product_screen.dart';
import '../extensions/context_tr.dart';
import '../main.dart';
import '../utils/responsive.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _adTimer;

  final List<Widget> _screens = [
    const HomeScreen(),
    const DiscoveryScreen(),
    const SizedBox.shrink(),
    const AiAssistantScreen(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    interstitialAdService.load();
    _adTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      interstitialAdService.tryShow();
    });
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
            child: IndexedStack(index: _currentIndex, children: _screens),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : _buildGlassNavBar(cs),
    );
  }

  Widget _buildGlassNavBar(ColorScheme cs) {
    final navItems = [
      _NavItem(Icons.storefront_outlined, Icons.storefront_rounded, context.tr('home'), 0, isChat: false),
      _NavItem(Icons.diamond_outlined, Icons.diamond_rounded, context.tr('discovery'), 1, isChat: false),
      _NavItem(Icons.add_rounded, Icons.add_rounded, '', 2, isChat: false, isSell: true),
      _NavItem(Icons.chat_outlined, Icons.chat_rounded, 'Chat', 3, isChat: true),
      _NavItem(Icons.person_outline, Icons.person_rounded, context.tr('profile'), 4, isChat: false),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 64, sigmaY: 64),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 32, offset: const Offset(0, 8)),
              ],
            ),
              child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: navItems.map((item) {
                if (item.isSell) {
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AddProductScreen()),
                        );
                      },
                      child: Transform.translate(
                        offset: const Offset(0, -28),
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: cs.primary.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 8)),
                              BoxShadow(color: cs.primary.withValues(alpha: 0.2), blurRadius: 48, offset: const Offset(0, 0)),
                            ],
                          ),
                          child: Icon(Icons.add_rounded, color: cs.onPrimary, size: 32),
                        ),
                      ),
                    ),
                  );
                }
                final isSelected = !item.isChat && _currentIndex == item.index;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (item.isChat) {
                        _openChats();
                      } else {
                        setState(() => _currentIndex = item.index);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? cs.primary.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isSelected ? item.activeIcon : item.icon,
                            color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: 0.45),
                            size: 24,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: 0.45),
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  void _openChats() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChatsListScreen()),
    );
  }

  Widget _buildSidebar(ColorScheme cs) {
    final navItems = [
      _NavItem(Icons.storefront_outlined, Icons.storefront_rounded, context.tr('home'), 0, isChat: false),
      _NavItem(Icons.diamond_outlined, Icons.diamond_rounded, context.tr('discovery'), 1, isChat: false),
      _NavItem(Icons.chat_outlined, Icons.chat_rounded, 'Chat', 0, isChat: true),
      _NavItem(Icons.rocket_launch_outlined, Icons.rocket_launch_rounded, 'AI', 3, isChat: false),
      _NavItem(Icons.person_outline, Icons.person_rounded, context.tr('profile'), 4, isChat: false),
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
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.7)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.store_rounded, color: cs.onPrimary, size: 20),
                ),
                const SizedBox(width: 12),
                Text('Soko Vibe', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: -0.3)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              children: navItems.map((item) {
                final isSelected = !item.isChat && _currentIndex == item.index;
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
                      onTap: () {
                        if (item.isChat) {
                          _openChats();
                        } else {
                          setState(() => _currentIndex = item.index);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? item.activeIcon : item.icon,
                              color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: 0.5),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(item.label, style: TextStyle(
                              color: isSelected ? cs.onSurface : cs.onSurface.withValues(alpha: 0.6),
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              fontSize: 14,
                            )),
                            const Spacer(),
                            if (isSelected)
                              Container(width: 6, height: 6,
                                decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
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
  final bool isChat;
  final bool isSell;
  const _NavItem(this.icon, this.activeIcon, this.label, this.index, {this.isChat = false, this.isSell = false});
}
