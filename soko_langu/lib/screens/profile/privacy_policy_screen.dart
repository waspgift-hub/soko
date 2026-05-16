import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('privacy_policy'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section(
                context.tr('pp_intro_title'),
                context.tr('pp_intro_body'),
              ),
              _section(
                context.tr('pp_info_title'),
                context.tr('pp_info_body'),
              ),
              _section(
                context.tr('pp_use_title'),
                context.tr('pp_use_body'),
              ),
              _section(
                context.tr('pp_share_title'),
                context.tr('pp_share_body'),
              ),
              _section(
                context.tr('pp_security_title'),
                context.tr('pp_security_body'),
              ),
              _section(
                context.tr('pp_contact_title'),
                context.tr('pp_contact_body'),
              ),
              const SizedBox(height: 40),
              Center(
                child: Text(
                  'Soko Langu © ${DateTime.now().year}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.5),
          ),
        ],
      ),
    );
  }
}
