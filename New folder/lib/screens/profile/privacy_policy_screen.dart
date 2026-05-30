import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('privacy_policy')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section(context.tr('privacy_info_collection'), [
                context.tr('privacy_info_collection_desc'),
              ]),
              _section(context.tr('privacy_info_use'), [
                context.tr('privacy_info_use_desc1'),
                context.tr('privacy_info_use_desc2'),
                context.tr('privacy_info_use_desc3'),
              ]),
              _section(context.tr('privacy_info_share'), [
                context.tr('privacy_info_share_desc'),
              ]),
              _section(context.tr('privacy_security'), [
                context.tr('privacy_security_desc'),
              ]),
              _section(context.tr('privacy_rights'), [
                context.tr('privacy_rights_desc1'),
                context.tr('privacy_rights_desc2'),
                context.tr('privacy_rights_desc3'),
              ]),
              _section(context.tr('privacy_contact'), [
                context.tr('privacy_contact_desc'),
              ]),
              const SizedBox(height: 20),
              Text(
                context.tr('privacy_last_updated'),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<String> paragraphs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D6A4F),
            ),
          ),
          const SizedBox(height: 8),
          ...paragraphs.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  p,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              )),
        ],
      ),
    );
  }
}
