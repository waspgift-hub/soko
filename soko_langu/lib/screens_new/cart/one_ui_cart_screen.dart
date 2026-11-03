import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../design_system/tokens/one_ui_tokens.dart';

class OneUiCartScreen extends StatelessWidget {
  const OneUiCartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
      appBar: AppBar(
        backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary),
        ),
        title: Text('Shopping Cart', style: TextStyle(color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 80,
              color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary,
            ),
            const SizedBox(height: OneUiSpacing.xl),
            Text(
              'Your cart is empty',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
              ),
            ),
            const SizedBox(height: OneUiSpacing.sm),
            Text(
              'Add items to get started',
              style: TextStyle(color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary),
            ),
            const SizedBox(height: OneUiSpacing.xxl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: OneUiSpacing.xxl),
              child: FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Continue Shopping'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
