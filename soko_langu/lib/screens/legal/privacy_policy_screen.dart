import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              Text(context.tr('pp_title'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: cs.primary)),
              const SizedBox(height: 4),
              Text(context.tr('pp_last_updated'), style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.6)),
                ),
                child: Text(
                  context.tr('pp_founder_summary'),
                  style: TextStyle(fontSize: 13.5, height: 1.6, color: cs.onSurface),
                ),
              ),

              const SizedBox(height: 8),

              _section(cs, context.tr('pp_section_1_title'), context.tr('pp_section_1_body')),
              _section(cs, context.tr('pp_section_2_title'), context.tr('pp_section_2_body')),
              _section(cs, context.tr('pp_section_3_title'), context.tr('pp_section_3_body')),
              _section(cs, context.tr('pp_section_4_title'), context.tr('pp_section_4_body')),
              _section(cs, context.tr('pp_section_5_title'), context.tr('pp_section_5_body')),
              _section(cs, context.tr('pp_section_6_title'), context.tr('pp_section_6_body')),
              _section(cs, context.tr('pp_section_7_title'), context.tr('pp_section_7_body')),
              _section(cs, context.tr('pp_section_8_title'), context.tr('pp_section_8_body')),
              _section(cs, context.tr('pp_section_9_title'), context.tr('pp_section_9_body')),
              _section(cs, context.tr('pp_section_10_title'), context.tr('pp_section_10_body')),
              _section(cs, context.tr('pp_section_11_title'), context.tr('pp_section_11_body')),
              _section(cs, context.tr('pp_section_12_title'), context.tr('pp_section_12_body')),
              _section(cs, context.tr('pp_section_13_title'), context.tr('pp_section_13_body')),
              _section(cs, context.tr('pp_section_14_title'), context.tr('pp_section_14_body')),
              _section(cs, context.tr('pp_section_15_title'), context.tr('pp_section_15_body')),
              _section(cs, context.tr('pp_section_16_title'), context.tr('pp_section_16_body')),
              _section(cs, context.tr('pp_section_17_title'), context.tr('pp_section_17_body')),
              _section(cs, context.tr('pp_section_18_title'), context.tr('pp_section_18_body')),

              const SizedBox(height: 32),
              Center(
                child: Text(context.tr('copyright'),
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(ColorScheme cs, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(fontSize: 14, height: 1.6, color: cs.onSurface.withValues(alpha: 0.75))),
        ],
      ),
    );
  }
}