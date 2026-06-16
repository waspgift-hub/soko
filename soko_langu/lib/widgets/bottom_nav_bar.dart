import 'dart:async';
import 'package:flutter/material.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/discovery_screen.dart';
import '../screens/ai/ai_assistant_screen.dart';

import '../extensions/context_tr.dart';
import '../main.dart';
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
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
       bottomNavigationBar: BottomNavigationBar(
         currentIndex: _currentIndex,
         onTap: (index) {
           setState(() {
             _currentIndex = index;
           });
         },
         type: BottomNavigationBarType.fixed,
         selectedItemColor: Theme.of(context).colorScheme.primary,
         unselectedItemColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
         items: [
           BottomNavigationBarItem(
             icon: Icon(Icons.storefront_outlined),
             activeIcon: Icon(Icons.storefront_rounded),
             label: context.tr('home'),
           ),
           BottomNavigationBarItem(
             icon: Icon(Icons.diamond_outlined),
             activeIcon: Icon(Icons.diamond_rounded),
             label: context.tr('discovery'),
           ),
            BottomNavigationBarItem(
              icon: Icon(Icons.rocket_launch_outlined),
              activeIcon: Icon(Icons.rocket_launch_rounded),
              label: 'AI',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.workspace_premium_outlined),
              activeIcon: Icon(Icons.workspace_premium_rounded),
              label: context.tr('profile'),
            ),
         ],
       ),
    );
  }
}
