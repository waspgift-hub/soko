import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('privacy_policy')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('privacy_policy'),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('pp_intro_body'),
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              _section(
                context,
                title: context.tr('pp_intro_title'),
                content: context.tr('pp_intro_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('pp_info_title'),
                content: context.tr('pp_info_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('pp_use_title'),
                content: context.tr('pp_use_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('pp_share_title'),
                content: context.tr('pp_share_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('pp_ai_title'),
                content: context.tr('pp_ai_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('pp_security_title'),
                content: context.tr('pp_security_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('pp_contact_title'),
                content: context.tr('pp_contact_body'),
              ),
              const SizedBox(height: 30),
              Center(
                child: Text(
                  context.tr('pp_last_updated'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, {required String title, required String content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          content,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
