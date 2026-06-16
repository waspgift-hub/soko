import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('terms_of_service')),
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
                context.tr('terms_of_service'),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('terms_intro'),
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              _section(
                context,
                title: context.tr('terms_s1_title'),
                content: context.tr('terms_s1_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('terms_s2_title'),
                content: context.tr('terms_s2_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('terms_s3_title'),
                content: context.tr('terms_s3_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('terms_s4_title'),
                content: context.tr('terms_s4_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('terms_s5_title'),
                content: context.tr('terms_s5_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('terms_s6_title'),
                content: context.tr('terms_s6_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('terms_s7_title'),
                content: context.tr('terms_s7_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('terms_s8_title'),
                content: context.tr('terms_s8_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('terms_s9_title'),
                content: context.tr('terms_s9_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('terms_s10_title'),
                content: context.tr('terms_s10_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('terms_s11_title'),
                content: context.tr('terms_s11_body'),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: context.tr('terms_s12_title'),
                content: context.tr('terms_s12_body'),
              ),
              const SizedBox(height: 30),
              Center(
                child: Text(
                  context.tr('terms_last_updated'),
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
