import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens external CTAs (WhatsApp, email) in a new tab.
Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uri.toString())),
      );
    }
  }
}
