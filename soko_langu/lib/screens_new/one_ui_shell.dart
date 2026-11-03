import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../app/routes.dart';
import '../../design_system/tokens/one_ui_tokens.dart';
import 'one_ui_home_screen.dart';
import 'discover/one_ui_discover_screen.dart';
import 'chat/one_ui_chats_screen.dart';
import 'profile/one_ui_profile_screen.dart';

class OneUiMainShell extends StatefulWidget {
  const OneUiMainShell({super.key});

  @override
  State<OneUiMainShell> createState() => _OneUiMainShellState();
}

class _OneUiMainShellState extends State<OneUiMainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    OneUiHomeScreen(),
    OneUiDiscoverScreen(),
    OneUiChatsScreen(),
    OneUiProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? OneUiColors.darkSurface : OneUiColors.surface,
          border: Border(
            top: BorderSide(
              color: isDark ? OneUiColors.darkBorder : OneUiColors.border,
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OneUiSpacing.md, vertical: OneUiSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, 'Home'),
                _buildNavItem(1, Icons.explore_rounded, Icons.explore_outlined, 'Discover'),
                _buildAddButton(),
                _buildNavItem(2, Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, 'Chats'),
                _buildNavItem(3, Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () {
        if (index >= 2 && FirebaseAuth.instance.currentUser == null) {
          context.push(AppRoutes.login);
          return;
        }
        HapticFeedback.selectionClick();
        setState(() => _currentIndex = index);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: OneUiAnimation.fast,
        padding: const EdgeInsets.symmetric(horizontal: OneUiSpacing.lg, vertical: OneUiSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: isSelected 
                ? OneUiColors.accent 
                : (isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary),
              size: 26,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected 
                  ? OneUiColors.accent 
                  : (isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: () {
        if (FirebaseAuth.instance.currentUser == null) {
          context.push(AppRoutes.login);
          return;
        }
        HapticFeedback.mediumImpact();
        context.push(AppRoutes.addProduct);
      },
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: OneUiColors.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: OneUiColors.accent.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.add_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}

    // Placeholder classes removed - using real screens
