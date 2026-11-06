import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens external links; same-origin paths open in the current tab context.
Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  final mode = uri.hasScheme
      ? LaunchMode.externalApplication
      : LaunchMode.platformDefault;
  if (!await launchUrl(uri, mode: mode, webOnlyWindowName: '_self')) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(uri.toString())));
    }
  }
}
