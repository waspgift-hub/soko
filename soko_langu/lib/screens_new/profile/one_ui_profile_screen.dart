import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../app/routes.dart';
import '../../design_system/tokens/one_ui_tokens.dart';

class OneUiProfileScreen extends StatelessWidget {
  const OneUiProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
      appBar: AppBar(
        backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
        title: Text('Profile', style: TextStyle(color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary)),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.settings),
            icon: Icon(Icons.settings_outlined, color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(OneUiSpacing.xl),
        children: [
          // Profile header
          Container(
            padding: const EdgeInsets.all(OneUiSpacing.xl),
            decoration: BoxDecoration(
              color: isDark ? OneUiColors.darkSurface : OneUiColors.surface,
              borderRadius: BorderRadius.circular(OneUiRadius.lg),
              border: Border.all(color: isDark ? OneUiColors.darkBorder : OneUiColors.border, width: 0.5),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: OneUiColors.accentContainer,
                  child: Icon(Icons.person, size: 36, color: OneUiColors.accent),
                ),
                const SizedBox(width: OneUiSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? 'User',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: OneUiSpacing.xs),
                      Text(
                        user?.email ?? 'Sign in to your account',
                        style: TextStyle(
                          color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (user != null)
                  IconButton(
                    onPressed: () => HapticFeedback.lightImpact(),
                    icon: Icon(Icons.edit_outlined, color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(height: OneUiSpacing.xl),
          // Menu items
          _buildMenuItem(context, Icons.shopping_bag_outlined, 'My Purchases', () => context.push('/oneui/orders')),
          _buildMenuItem(context, Icons.storefront_outlined, 'My Ads', () => context.push(AppRoutes.myAds)),
          _buildMenuItem(context, Icons.favorite_outline_rounded, 'Wishlist', () => context.push(AppRoutes.wishlist)),
          _buildMenuItem(context, Icons.account_balance_wallet_outlined, 'Wallet', () => {}),
          _buildMenuItem(context, Icons.business_center_outlined, 'Seller Dashboard', () => context.push(AppRoutes.sellerDashboard)),
          _buildMenuItem(context, Icons.chat_bubble_outline_rounded, 'Messages', () => {}),
          _buildMenuItem(context, Icons.settings_outlined, 'Settings', () => context.push('/oneui/settings')),
          _buildMenuItem(context, Icons.help_outline_rounded, 'Help & Support', () => context.push(AppRoutes.help)),
          _buildMenuItem(context, Icons.business_outlined, 'Company OS', () => context.push(AppRoutes.companyConsole)),
          const SizedBox(height: OneUiSpacing.xl),
          if (user == null)
            FilledButton(
              onPressed: () => context.push('/oneui/login'),
              child: const Text('Sign In'),
            )
          else
            ElevatedButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) context.go('/oneui/shell');
              },
              child: const Text('Sign Out'),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: OneUiSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? OneUiColors.darkSurface : OneUiColors.surface,
        borderRadius: BorderRadius.circular(OneUiRadius.lg),
        border: Border.all(color: isDark ? OneUiColors.darkBorder : OneUiColors.border, width: 0.5),
      ),
      child: ListTile(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        leading: Icon(icon, color: OneUiColors.accent),
        title: Text(
          title,
          style: TextStyle(color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OneUiRadius.lg)),
      ),
    );
  }
}
