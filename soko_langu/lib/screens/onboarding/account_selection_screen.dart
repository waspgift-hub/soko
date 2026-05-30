import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';

class AccountSelectionScreen extends StatelessWidget {
  const AccountSelectionScreen({super.key});

  Future<void> _select(String tier, BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_tier', tier);
    if (context.mounted) {
      context.replace(AppRoutes.register);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Icon(Icons.storefront_rounded, size: 72, color: cs.primary),
              const SizedBox(height: 16),
              Text(
                context.tr('onboarding_welcome_title'),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Jionee mwenyewe/Look for yourself',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const Spacer(flex: 1),
              _AccountCard(
                icon: Icons.shopping_bag_outlined,
                titleKey: 'account_buyer',
                descKey: 'account_buyer_desc',
                color: const Color(0xFF2D6A4F),
                onTap: () => _select('buyer', context),
              ),
              const SizedBox(height: 14),
              _AccountCard(
                icon: Icons.store_outlined,
                titleKey: 'account_seller',
                descKey: 'account_seller_desc',
                color: const Color(0xFF6C63FF),
                onTap: () => _select('seller', context),
              ),
              const SizedBox(height: 14),
              _AccountCard(
                icon: Icons.swap_horiz_rounded,
                titleKey: 'account_both',
                descKey: 'account_both_desc',
                color: const Color(0xFF0088CC),
                onTap: () => _select('both', context),
              ),
              const Spacer(flex: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    context.tr('account_already'),
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                  TextButton(
                    onPressed: () => context.replace(AppRoutes.login),
                    child: Text(
                      context.tr('login_prompt'),
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final IconData icon;
  final String titleKey;
  final String descKey;
  final Color color;
  final VoidCallback onTap;

  const _AccountCard({
    required this.icon,
    required this.titleKey,
    required this.descKey,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(titleKey),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr(descKey),
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}
