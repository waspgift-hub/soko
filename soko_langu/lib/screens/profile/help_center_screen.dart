import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('help'))),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            8 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            children: [
              _buildSection(
                icon: Icons.rocket_launch,
                title: context.tr('getting_started'),
                subtitle: context.tr('getting_started_sub'),
                children: [
                  _helpTile(
                    title: context.tr('register_login'),
                    content: context.tr('help_register_login'),
                  ),
                  _helpTile(
                    title: context.tr('choose_account_type'),
                    content: context.tr('help_account_types'),
                  ),
                  _helpTile(
                    title: context.tr('browsing_products'),
                    content: context.tr('help_browsing'),
                  ),
                  _helpTile(
                    title: context.tr('buying'),
                    content: context.tr('help_buying'),
                  ),
                ],
              ),

              _buildSection(
                icon: Icons.store,
                title: context.tr('selling_title'),
                subtitle: context.tr('selling_sub'),
                children: [
                  _helpTile(
                    title: context.tr('list_product'),
                    content: context.tr('help_list_product'),
                  ),
                  _helpTile(
                    title: context.tr('manage_orders'),
                    content: context.tr('help_manage_orders'),
                  ),
                  _helpTile(
                    title: context.tr('seller_dashboard'),
                    content: context.tr('help_seller_dashboard'),
                  ),
                  _helpTile(
                    title: context.tr('boosting'),
                    content: context.tr('help_boosting'),
                  ),
                  _helpTile(
                    title: context.tr('flash_sales'),
                    content: context.tr('help_flash_sales'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildSection(
                icon: Icons.chat,
                title: context.tr('communication'),
                subtitle: context.tr('communication_sub'),
                children: [
                  _helpTile(
                    title: context.tr('chat_feature'),
                    content: context.tr('help_chat'),
                  ),
                  _helpTile(
                    title: context.tr('audio_music'),
                    content: context.tr('help_audio'),
                  ),
                  _helpTile(
                    title: context.tr('youtube_music'),
                    content: context.tr('help_youtube'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildSection(
                icon: Icons.verified_user,
                title: context.tr('account_verification'),
                subtitle: context.tr('verification_sub'),
                children: [
                  _helpTile(
                    title: context.tr('kyc'),
                    content: context.tr('help_kyc'),
                  ),
                  _helpTile(
                    title: context.tr('app_lock'),
                    content: context.tr('help_app_lock'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildSection(
                icon: Icons.contact_mail,
                title: context.tr('contact'),
                subtitle: context.tr('wasiliana'),
                children: [
                  _helpTile(
                    title: context.tr('email'),
                    content: 'langusoko@gmail.com',
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        collapsedBackgroundColor: Colors.transparent,
        backgroundColor: Theme.of(context).colorScheme.surface,
        collapsedShape: const RoundedRectangleBorder(),
        shape: const RoundedRectangleBorder(),
        iconColor: Theme.of(context).colorScheme.primary,
        collapsedIconColor: Theme.of(context).colorScheme.primary,
        children: children,
      ),
    );
  }

  Widget _helpTile({required String title, required String content}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Text(
              content,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
