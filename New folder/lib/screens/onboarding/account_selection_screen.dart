import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../services/user_service.dart';
import '../../extensions/context_tr.dart';
import '../../main.dart';
import '../profile/premium_upgrade_screen.dart';
import '../../app/routes.dart';

class AccountSelectionScreen extends StatefulWidget {
  const AccountSelectionScreen({super.key});

  @override
  State<AccountSelectionScreen> createState() => _AccountSelectionScreenState();
}

class _AccountSelectionScreenState extends State<AccountSelectionScreen> {
  String _selectedTier = 'free';
  bool _isSaving = false;

  Future<void> _continue() async {
    if (_selectedTier == 'free') {
      await _goToMain();
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!mounted) return;
    final paid = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PremiumUpgradeScreen(initialTier: _selectedTier),
      ),
    );

    if (paid == true && mounted) {
      await _goToMain();
    }
  }

  Future<void> _goToMain() async {
    setState(() => _isSaving = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await UserService()
            .setAccountTier(user.uid, _selectedTier)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('AccountSelection setTier: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tier save failed, continuing anyway: $e')),
          );
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    await prefs.setString('account_tier', _selectedTier);

    if (mounted) {
      AppConfig.of(context).onSetTier(_selectedTier);
      context.replace(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(context).padding.bottom + 24,
          ),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Icon(Icons.store, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              Text(
                context.tr('welcome_soko'),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('choose_account'),
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _accountCard(
                tier: 'free',
                title: context.tr('free'),
                price: 'TSh 0',
                period: context.tr('forever'),
                features: [
                  context.tr('free_feature_list'),
                  context.tr('free_feature_ads'),
                ],
                color: Colors.green,
              ),
              const SizedBox(height: 12),
              _accountCard(
                tier: 'premium',
                title: context.tr('premium'),
                price: 'TSh 25,000',
                period: context.tr('per_month'),
                features: [
                  context.tr('premium_no_ads'),
                  context.tr('premium_feature_support'),
                  context.tr('premium_feature_badges'),
                ],
                color: Colors.amber,
              ),
              const SizedBox(height: 12),
              _accountCard(
                tier: 'silver',
                title: context.tr('silver'),
                price: 'TSh 10,000',
                period: context.tr('per_month'),
                features: [
                  context.tr('silver_feature_visibility'),
                  context.tr('silver_feature_badge'),
                  context.tr('silver_feature_support'),
                  context.tr('premium_no_ads'),
                ],
                color: Colors.blueGrey,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedTier == 'silver'
                        ? Colors.blueGrey
                        : _selectedTier == 'premium'
                        ? Colors.amber
                        : Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isSaving ? null : _continue,
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          _selectedTier == 'free'
                              ? context.tr('continue_free')
                              : context.tr('pay_now'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isSaving ? null : _continue,
                child: Text(
                  context.tr('skip_choose'),
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountCard({
    required String tier,
    required String title,
    required String price,
    required String period,
    required List<String> features,
    required Color color,
  }) {
    final isSelected = _selectedTier == tier;
    return GestureDetector(
      onTap: () => setState(() => _selectedTier = tier),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$price/$period',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? color
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(Icons.check, color: color, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              f,
                              style: TextStyle(
                                fontSize: 13,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(context).colorScheme.onSurface
                                          .withOpacity(0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 28)
            else
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[400]!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

