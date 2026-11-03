import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design_system/tokens/one_ui_tokens.dart';

class OneUiChatsScreen extends StatelessWidget {
  const OneUiChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
      appBar: AppBar(
        backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
        title: Text('Chats', style: TextStyle(color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary)),
        actions: [
          IconButton(
            onPressed: () => HapticFeedback.lightImpact(),
            icon: Icon(Icons.edit_outlined, color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary,
            ),
            const SizedBox(height: OneUiSpacing.lg),
            Text(
              'No chats yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
              ),
            ),
            const SizedBox(height: OneUiSpacing.sm),
            Text(
              'Start a conversation with sellers',
              style: TextStyle(color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
