import 'dart:async';
import 'package:flutter/material.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/discovery_screen.dart';
import '../screens/ai/ai_assistant_screen.dart';
import '../screens/chat/chats_list_screen.dart';
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
          : Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  if (index == 2) {
                    _openChats();
                  } else {
                    setState(() => _currentIndex = index);
                  }
                },
                backgroundColor: cs.surface.withValues(alpha: 0.92),
                indicatorColor: cs.primary.withValues(alpha: 0.12),
                height: 64,
                labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
                shadowColor: Colors.transparent,
                elevation: 0,
                destinations: [
                  NavigationDestination(
                    icon: Icon(Icons.storefront_outlined, color: cs.onSurface.withValues(alpha: 0.45)),
                    selectedIcon: Icon(Icons.storefront_rounded, color: cs.primary),
                    label: context.tr('home'),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.diamond_outlined, color: cs.onSurface.withValues(alpha: 0.45)),
                    selectedIcon: Icon(Icons.diamond_rounded, color: cs.primary),
                    label: context.tr('discovery'),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.chat_outlined, color: cs.onSurface.withValues(alpha: 0.45)),
                    selectedIcon: Icon(Icons.chat_rounded, color: cs.primary),
                    label: 'Chat',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.rocket_launch_outlined, color: cs.onSurface.withValues(alpha: 0.45)),
                    selectedIcon: Icon(Icons.rocket_launch_rounded, color: cs.primary),
                    label: 'AI',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline, color: cs.onSurface.withValues(alpha: 0.45)),
                    selectedIcon: Icon(Icons.person_rounded, color: cs.primary),
                    label: context.tr('profile'),
                  ),
                ],
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
      _SidebarItem(Icons.storefront_outlined, Icons.storefront_rounded, context.tr('home'), 0, isChat: false),
      _SidebarItem(Icons.diamond_outlined, Icons.diamond_rounded, context.tr('discovery'), 1, isChat: false),
      _SidebarItem(Icons.chat_outlined, Icons.chat_rounded, 'Chat', 0, isChat: true),
      _SidebarItem(Icons.rocket_launch_outlined, Icons.rocket_launch_rounded, 'AI', 3, isChat: false),
      _SidebarItem(Icons.person_outline, Icons.person_rounded, context.tr('profile'), 4, isChat: false),
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

class _SidebarItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final bool isChat;
  const _SidebarItem(this.icon, this.activeIcon, this.label, this.index, {this.isChat = false});
}
