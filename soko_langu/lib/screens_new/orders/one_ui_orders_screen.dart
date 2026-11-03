import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../design_system/tokens/one_ui_tokens.dart';

class OneUiOrdersScreen extends StatelessWidget {
  const OneUiOrdersScreen({super.key});

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
        title: Text('My Purchases', style: TextStyle(color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary)),
        bottom: TabBar(
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Pending'),
            Tab(text: 'In Progress'),
            Tab(text: 'Completed'),
          ],
          labelColor: OneUiColors.accent,
          unselectedLabelColor: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary,
          indicatorColor: OneUiColors.accent,
        ),
      ),
      body: TabBarView(
        children: [
          _buildEmptyState(context, isDark),
          _buildEmptyState(context, isDark),
          _buildEmptyState(context, isDark),
          _buildEmptyState(context, isDark),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 80,
            color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary,
          ),
          const SizedBox(height: OneUiSpacing.xl),
          Text(
            'No orders yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
            ),
          ),
          const SizedBox(height: OneUiSpacing.sm),
          Text(
            'Your orders will appear here',
            style: TextStyle(color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
