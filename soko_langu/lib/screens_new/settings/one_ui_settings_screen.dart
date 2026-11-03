import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../design_system/tokens/one_ui_tokens.dart';

class OneUiSettingsScreen extends StatelessWidget {
  const OneUiSettingsScreen({super.key});

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
        title: Text('Settings', style: TextStyle(color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(OneUiSpacing.xl),
        children: [
          _buildSection('Account', [
            _buildTile(Icons.person_outline_rounded, 'Edit Profile', () {}),
            _buildTile(Icons.lock_outline_rounded, 'Security', () {}),
            _buildTile(Icons.verified_user_outlined, 'Verification', () {}),
          ]),
          const SizedBox(height: OneUiSpacing.xl),
          _buildSection('Preferences', [
            _buildTile(Icons.notifications_none_rounded, 'Notifications', () {}),
            _buildTile(Icons.language_rounded, 'Language', () {}),
            _buildTile(Icons.dark_mode_outlined, 'Appearance', () {}),
          ]),
          const SizedBox(height: OneUiSpacing.xl),
          _buildSection('Support', [
            _buildTile(Icons.help_outline_rounded, 'Help Center', () {}),
            _buildTile(Icons.info_outline_rounded, 'About', () {}),
            _buildTile(Icons.privacy_tip_outlined, 'Privacy Policy', () {}),
            _buildTile(Icons.description_outlined, 'Terms of Service', () {}),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: OneUiSpacing.sm, bottom: OneUiSpacing.md),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? OneUiColors.darkSurface : OneUiColors.surface,
            borderRadius: BorderRadius.circular(OneUiRadius.lg),
            border: Border.all(color: isDark ? OneUiColors.darkBorder : OneUiColors.border, width: 0.5),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildTile(IconData icon, String title, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      leading: Icon(icon, color: OneUiColors.accent),
      title: Text(title, style: TextStyle(color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary)),
      trailing: Icon(Icons.chevron_right_rounded, color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary),
    );
  }
}
